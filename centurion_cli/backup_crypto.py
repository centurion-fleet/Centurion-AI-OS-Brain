"""Encrypted Centurion backup container.

WHY THIS EXISTS
---------------
`centurion backup` writes a plain zip. Compressed, not encrypted. Inside it are
the practice's documents, client files and correspondence; the vault is encrypted
but the files around it are not. On a removable drive in a desk drawer that is a
UK GDPR exposure, and it surfaces after a burglary rather than before.

So an archive that leaves the machine is encrypted at rest, with a passphrase the
CUSTOMER holds. We never hold it. If we held it we could read the archive, and
then we are in possession of their data — the exact thing the whole product is
designed to avoid.

TWO CONTAINER GENERATIONS
-------------------------
v1 (`.cbk`, magic `CENTBK1`) is what 7.0.13 and 7.1.x shipped: the record key is
derived from the passphrase directly. It is still read, byte for byte, because
archives already in customers' drawers must open in every future release.

v2 (magic `CENTBK2`) exists for ONE reason, and it is §6.3 of the Editions plan:

    **No recovery key is printed. The plan promises a business-recoverable,
    vendor-unrecoverable mistake. Nothing ships that.**

v1 cannot carry that promise. Its key IS the passphrase, so a forgotten
passphrase is an unreadable archive, full stop. v2 fixes it the only honest way:
the archive is encrypted with a random 256-bit data key (`DEK`), and that DEK is
wrapped TWICE — once under the passphrase, once under a printed recovery key.
Either opens the archive. We hold neither.

    A lost passphrase then becomes a recoverable mistake for a business and an
    unrecoverable one for us, which is exactly the trade the plan asks for.

CONTAINER FORMAT — v1 (`.cbk`)
------------------------------
    magic           8   b"CENTBK1\\0"
    kdf_id          1   1 = scrypt(n=2**15, r=8, p=1)
    salt           16   random per archive
    chunk_size      4   big-endian, plaintext bytes per record
    plaintext_len   8   big-endian, total plaintext bytes
    nonce_prefix    4   random per archive
    plaintext_sha   32  SHA-256 of the plaintext, filled in after streaming
    ---- records, each: ciphertext || tag(16) ----
    nonce = nonce_prefix(4) || counter(8, big-endian)
    aad   = header_bytes || counter(8, big-endian)

CONTAINER FORMAT — v2 (`CENTBK2`)
---------------------------------
    magic           8   b"CENTBK2\\0"
    kdf_id          1   1 = scrypt for the passphrase wrap
    flags           1   bit0 = recovery slot populated
    chunk_size      4
    plaintext_len   8
    nonce_prefix    4
    plaintext_sha  32   filled in after streaming
    pass_salt      16
    pass_nonce     12
    pass_wrap      48   AESGCM(scrypt(passphrase, pass_salt)).encrypt(DEK)
    rec_salt       16   zeros when no recovery slot
    rec_nonce      12
    rec_wrap       48   AESGCM(scrypt(recovery_key, rec_salt)).encrypt(DEK)
    ---- records, identical framing to v1, but keyed with the DEK ----

Each wrap is bound to its own slot by a distinct AAD (b"CENTBK2-pass" /
b"CENTBK2-recovery"), so a recovery wrap cannot be substituted for a passphrase
wrap. The header's trailing SHA is excluded from the record AAD for the same
reason as v1: it is written after the records exist.

AES-256-GCM per record, so the plaintext is never held in memory whole and a
100 MB home does not need 100 MB of RAM. Any single flipped byte fails that
record's tag and the whole restore aborts — there is no partial-archive path,
because a backup that restores "most" of a practice's files is worse than one
that refuses.

VERIFICATION IS NOT OPTIONAL
----------------------------
`verify_archive` decrypts the whole thing, compares the plaintext digest, and
runs `zipfile.testzip()` over every entry. A backup nobody checked is not a
backup. The machine must not be able to claim one it has not proven.
"""

from __future__ import annotations

import getpass
import hashlib
import os
import struct
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any, Optional

MAGIC = b"CENTBK1\x00"
MAGIC_V2 = b"CENTBK2\x00"
KDF_SCRYPT = 1
FLAG_RECOVERY = 0b0000_0001
_SALT_LEN = 16
_NONCE_PREFIX_LEN = 4
_TAG_LEN = 16
_KEY_LEN = 32
_DEFAULT_CHUNK = 1024 * 1024  # 1 MiB plaintext per record
_SCRYPT_N = 2**15
_SCRYPT_R = 8
_SCRYPT_P = 1

HEADER_STRUCT = struct.Struct(">8sB16sIQI32s")  # magic kdf salt chunk len nonce sha
HEADER_LEN = HEADER_STRUCT.size  # 73
_SHA_OFFSET = HEADER_LEN - 32

# v2: magic kdf flags chunk len nonce sha pass_salt pass_nonce pass_wrap
#     rec_salt rec_nonce rec_wrap
HEADER_V2_STRUCT = struct.Struct(">8sBB4sQ4s32s16s12s48s16s12s48s")
HEADER_V2_LEN = HEADER_V2_STRUCT.size  # 210
_SHA_OFFSET_V2 = 26  # 8 + 1 + 1 + 4 + 8 + 4 — everything the records bind to

_WRAP_LEN = _KEY_LEN + _TAG_LEN  # 48
_GCM_NONCE_LEN = 12
_AAD_PASS = b"CENTBK2-pass"
_AAD_RECOVERY = b"CENTBK2-recovery"

# A printed recovery key: 20 random bytes → 32 Crockford-base32 characters → 8
# groups of 4. 160 bits is comfortable for something a principal reads off a
# sheet of paper, and scrypt on top of it means a stolen archive is still slow
# to attack.
#
# Crockford's alphabet, not RFC 4648's, and the difference is the whole point:
# RFC 4648 base32 contains I, L and O, so a key read down a telephone becomes
# "is that a one or an I?" Crockford removes I, L, O and U, and normalisation
# folds the four characters people still type anyway.
_RECOVERY_BYTES = 20
_RECOVERY_GROUP = 4
_CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_CROCKFORD_FOLD = str.maketrans({"O": "0", "I": "1", "L": "1", "U": "V"})


class BackupCryptoError(RuntimeError):
    """Base class for anything that stops an archive being trusted."""


class WrongPassphrase(BackupCryptoError):
    """The archive did not authenticate. Wrong passphrase, or it was tampered with.

    Deliberately one error for both: GCM cannot tell you which, and telling the
    customer "your passphrase is wrong" when the drive is corrupt sends them
    hunting for the wrong problem.
    """


class NotAnEncryptedArchive(BackupCryptoError):
    """The file does not carry our magic — it is a plain zip or something else."""


class RecoveryKeyNeeded(BackupCryptoError):
    """The archive carries a recovery key and the passphrase did not open it.

    Its own class because the customer action is completely different: do not go
    looking for a mistyped passphrase, go and get the printed sheet out of the
    safe. Saying "wrong passphrase" here is the sentence that loses the data.
    """


# ── recovery keys ────────────────────────────────────────────────────────────


def _crockford32(data: bytes) -> str:
    """Encode bytes as Crockford base32 — 160 bits in, 32 characters out."""
    bits = "".join(f"{b:08b}" for b in data)
    bits += "0" * (-len(bits) % 5)
    return "".join(_CROCKFORD[int(bits[i : i + 5], 2)] for i in range(0, len(bits), 5))


def generate_recovery_key() -> str:
    """A printable recovery key, grouped for reading off paper.

    Crockford base32 rather than hex: no I, L, O or U in the output, lower case
    is folded on entry, and the four characters people type anyway (O for zero,
    I and L for one, U for V) are folded too — so a key copied by hand out of a
    safe still opens the archive.
    """
    raw = _crockford32(os.urandom(_RECOVERY_BYTES))
    return "-".join(
        raw[i : i + _RECOVERY_GROUP] for i in range(0, len(raw), _RECOVERY_GROUP)
    )


def normalise_recovery_key(key: str) -> str:
    """Accept what a human types: any case, dashes, spaces, and O/I/L/U slips."""
    cleaned = "".join(ch for ch in (key or "").upper() if ch.isalnum())
    cleaned = cleaned.translate(_CROCKFORD_FOLD)
    if not cleaned:
        raise BackupCryptoError("A recovery key is required.")
    return cleaned


# ── key derivation ───────────────────────────────────────────────────────────


def is_encrypted(path: os.PathLike | str) -> bool:
    """True when the file starts with either container magic."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(len(MAGIC))
            return head == MAGIC or head == MAGIC_V2
    except OSError:
        return False


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

    if not passphrase:
        raise BackupCryptoError("A passphrase is required. An empty passphrase is not encryption.")
    kdf = Scrypt(salt=salt, length=_KEY_LEN, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P)
    return kdf.derive(passphrase.encode("utf-8"))


def _aad(header: bytes, counter: int, *, sha_offset: int = _SHA_OFFSET) -> bytes:
    """Bind each record to the header — but only its immutable part.

    The trailing SHA-256 is filled in AFTER the plaintext has been streamed, so
    it cannot take part in the authentication of records written before it is
    known. Excluding it is what makes encrypt and decrypt agree on the AAD.
    """
    return header[:sha_offset] + counter.to_bytes(8, "big")


def _nonce(prefix: bytes, counter: int) -> bytes:
    return prefix + counter.to_bytes(8, "big")


# ── streaming ────────────────────────────────────────────────────────────────


def _stream_encrypt(
    src: Path,
    dst: Path,
    key: bytes,
    header: bytes,
    nonce_prefix: bytes,
    chunk_size: int,
    sha_offset: int,
) -> dict[str, Any]:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    aead = AESGCM(key)
    digest = hashlib.sha256()
    written = 0
    counter = 0

    tmp_dst = dst.with_suffix(dst.suffix + ".part")
    try:
        with open(src, "rb") as fin, open(tmp_dst, "wb") as fout:
            fout.write(header)
            while True:
                block = fin.read(chunk_size)
                if not block:
                    break
                digest.update(block)
                ct = aead.encrypt(
                    _nonce(nonce_prefix, counter), block, _aad(header, counter, sha_offset=sha_offset)
                )
                fout.write(ct)
                written += len(block)
                counter += 1
            # Fill the digest in now that the whole plaintext has been read.
            fout.seek(sha_offset)
            fout.write(digest.digest())
            fout.flush()
            os.fsync(fout.fileno())
        os.replace(tmp_dst, dst)
    except Exception:
        tmp_dst.unlink(missing_ok=True)
        raise

    return {
        "archive": str(dst),
        "plaintext_bytes": written,
        "archive_bytes": dst.stat().st_size,
        "records": counter,
        "sha256": digest.hexdigest(),
    }


def _stream_decrypt(
    fin,
    dst: Path,
    key: bytes,
    raw_header: bytes,
    chunk_size: int,
    plaintext_len: int,
    nonce_prefix: bytes,
    sha: bytes,
    sha_offset: int,
    *,
    recovery_slot: bool = False,
) -> dict[str, Any]:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    aead = AESGCM(key)
    digest = hashlib.sha256()
    remaining = plaintext_len
    counter = 0
    tmp_dst = dst.with_suffix(dst.suffix + ".part")
    try:
        with open(tmp_dst, "wb") as fout:
            while remaining > 0:
                n = min(chunk_size, remaining)
                blob = fin.read(n + _TAG_LEN)
                if len(blob) != n + _TAG_LEN:
                    raise WrongPassphrase(
                        "Archive ended early — the file is truncated or damaged."
                    )
                try:
                    block = aead.decrypt(
                        _nonce(nonce_prefix, counter),
                        blob,
                        _aad(raw_header, counter, sha_offset=sha_offset),
                    )
                except Exception as exc:  # InvalidTag and variants
                    raise WrongPassphrase(
                        "Archive did not authenticate — the passphrase is wrong, "
                        "or the file has been altered."
                    ) from exc
                digest.update(block)
                fout.write(block)
                remaining -= n
                counter += 1
            fout.flush()
            os.fsync(fout.fileno())
        os.replace(tmp_dst, dst)
    except Exception:
        tmp_dst.unlink(missing_ok=True)
        raise

    actual = digest.digest()
    if actual != sha:
        Path(dst).unlink(missing_ok=True)
        raise BackupCryptoError(
            "Archive decrypted but does not match its own digest — treat as damaged and use an earlier backup."
        )

    return {
        "zip": str(dst),
        "plaintext_bytes": plaintext_len,
        "records": counter,
        "sha256": actual.hex(),
        "recovery_slot": recovery_slot,
    }


# ── encrypt ──────────────────────────────────────────────────────────────────


def encrypt_file(
    src: os.PathLike | str,
    dst: os.PathLike | str,
    passphrase: str,
    *,
    chunk_size: int = _DEFAULT_CHUNK,
    remove_source: bool = False,
    recovery_key: Optional[str] = None,
) -> dict[str, Any]:
    """Encrypt `src` into a `.cbk` container at `dst`. Returns stats.

    With `recovery_key`, writes a **v2** container whose data key is wrapped by
    both the passphrase and that key — either opens it. Without one, writes the
    established v1 container, so nothing that does not ask for a recovery key
    changes shape or behaviour.

    The plaintext digest is computed during the pass and written back into the
    header at the end, so verification needs no second read of the source.
    """
    src, dst = Path(src), Path(dst)
    if not passphrase:
        raise BackupCryptoError("A passphrase is required. An empty passphrase is not encryption.")

    if recovery_key:
        stats = _encrypt_v2(src, dst, passphrase, chunk_size, recovery_key)
        stats["container"] = "v2"
        stats["recovery_key_present"] = True
    else:
        stats = _encrypt_v1(src, dst, passphrase, chunk_size)
        stats["container"] = "v1"
        stats["recovery_key_present"] = False

    if remove_source:
        src.unlink(missing_ok=True)
    return stats


def _encrypt_v1(src: Path, dst: Path, passphrase: str, chunk_size: int) -> dict[str, Any]:
    salt = os.urandom(_SALT_LEN)
    nonce_prefix = os.urandom(_NONCE_PREFIX_LEN)
    plaintext_len = src.stat().st_size
    header = HEADER_STRUCT.pack(
        MAGIC, KDF_SCRYPT, salt, chunk_size, plaintext_len, int.from_bytes(nonce_prefix, "big"), b"\x00" * 32
    )
    key = _derive_key(passphrase, salt)
    return _stream_encrypt(src, dst, key, header, nonce_prefix, chunk_size, _SHA_OFFSET)


def _encrypt_v2(
    src: Path, dst: Path, passphrase: str, chunk_size: int, recovery_key: str
) -> dict[str, Any]:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    dek = os.urandom(_KEY_LEN)
    nonce_prefix = os.urandom(_NONCE_PREFIX_LEN)
    plaintext_len = src.stat().st_size

    pass_salt = os.urandom(_SALT_LEN)
    pass_nonce = os.urandom(_GCM_NONCE_LEN)
    pass_wrap = AESGCM(_derive_key(passphrase, pass_salt)).encrypt(pass_nonce, dek, _AAD_PASS)
    assert len(pass_wrap) == _WRAP_LEN

    rec_salt = os.urandom(_SALT_LEN)
    rec_nonce = os.urandom(_GCM_NONCE_LEN)
    normalised = normalise_recovery_key(recovery_key)
    rec_wrap = AESGCM(_derive_key(normalised, rec_salt)).encrypt(rec_nonce, dek, _AAD_RECOVERY)
    assert len(rec_wrap) == _WRAP_LEN

    header = HEADER_V2_STRUCT.pack(
        MAGIC_V2,
        KDF_SCRYPT,
        FLAG_RECOVERY,
        chunk_size.to_bytes(4, "big"),
        plaintext_len,
        nonce_prefix,
        b"\x00" * 32,
        pass_salt,
        pass_nonce,
        pass_wrap,
        rec_salt,
        rec_nonce,
        rec_wrap,
    )
    return _stream_encrypt(src, dst, dek, header, nonce_prefix, chunk_size, _SHA_OFFSET_V2)


# ── decrypt ──────────────────────────────────────────────────────────────────


def decrypt_file(
    src: os.PathLike | str,
    dst: os.PathLike | str,
    passphrase: str,
    *,
    expect_sha256: Optional[str] = None,
    recovery_key: Optional[str] = None,
) -> dict[str, Any]:
    """Decrypt a `.cbk` container to `dst`.

    Raises WrongPassphrase when nothing opens it, and RecoveryKeyNeeded when the
    archive carries a recovery slot but the passphrase failed and no recovery key
    was supplied — a different instruction to the reader.
    """
    src, dst = Path(src), Path(dst)
    with open(src, "rb") as fin:
        magic = fin.read(len(MAGIC))
        if magic == MAGIC:
            result = _decrypt_v1(fin, dst, passphrase)
        elif magic == MAGIC_V2:
            result = _decrypt_v2(fin, dst, passphrase, recovery_key)
        else:
            raise NotAnEncryptedArchive(
                "Not an encrypted Centurion backup (no container magic)."
            )

    if expect_sha256 and expect_sha256.lower() != result["sha256"]:
        Path(dst).unlink(missing_ok=True)
        raise BackupCryptoError("Archive digest does not match the expected value.")
    return result


def _decrypt_v1(fin, dst: Path, passphrase: str) -> dict[str, Any]:
    rest = fin.read(HEADER_LEN - len(MAGIC))
    raw_header = MAGIC + rest
    if len(raw_header) != HEADER_LEN:
        raise NotAnEncryptedArchive("File is too short to be a Centurion backup container.")
    _, kdf_id, salt, chunk_size, plaintext_len, nonce_seed, sha = HEADER_STRUCT.unpack(raw_header)
    if kdf_id != KDF_SCRYPT:
        raise BackupCryptoError(f"Unsupported key-derivation id {kdf_id}.")
    if chunk_size <= 0 or chunk_size > 64 * 1024 * 1024:
        raise BackupCryptoError(f"Refusing implausible chunk size {chunk_size}.")
    nonce_prefix = nonce_seed.to_bytes(_NONCE_PREFIX_LEN, "big")
    if not passphrase:
        # A v1 container carries no wrap block, so no recovery key can open it.
        # Saying "a passphrase is required" here would send a customer looking
        # for the wrong document; name the actual limit.
        raise BackupCryptoError(
            "This archive was written without a recovery key, so the passphrase is "
            "the only way in. Check the passphrase sheet in the practice safe."
        )
    key = _derive_key(passphrase, salt)
    return _stream_decrypt(
        fin, dst, key, raw_header, chunk_size, plaintext_len, nonce_prefix, sha, _SHA_OFFSET
    )


def _decrypt_v2(
    fin, dst: Path, passphrase: str, recovery_key: Optional[str]
) -> dict[str, Any]:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    rest = fin.read(HEADER_V2_LEN - len(MAGIC_V2))
    raw_header = MAGIC_V2 + rest
    if len(raw_header) != HEADER_V2_LEN:
        raise NotAnEncryptedArchive("File is too short to be a Centurion backup container.")
    (
        _magic,
        kdf_id,
        flags,
        chunk_raw,
        plaintext_len,
        nonce_prefix,
        sha,
        pass_salt,
        pass_nonce,
        pass_wrap,
        rec_salt,
        rec_nonce,
        rec_wrap,
    ) = HEADER_V2_STRUCT.unpack(raw_header)

    if kdf_id != KDF_SCRYPT:
        raise BackupCryptoError(f"Unsupported key-derivation id {kdf_id}.")
    chunk_size = int.from_bytes(chunk_raw, "big")
    if chunk_size <= 0 or chunk_size > 64 * 1024 * 1024:
        raise BackupCryptoError(f"Refusing implausible chunk size {chunk_size}.")

    has_recovery = bool(flags & FLAG_RECOVERY)

    dek = None
    used_recovery = False
    if passphrase:
        try:
            dek = AESGCM(_derive_key(passphrase, pass_salt)).decrypt(
                pass_nonce, pass_wrap, _AAD_PASS
            )
        except Exception:
            dek = None

    if dek is None and recovery_key:
        try:
            dek = AESGCM(_derive_key(normalise_recovery_key(recovery_key), rec_salt)).decrypt(
                rec_nonce, rec_wrap, _AAD_RECOVERY
            )
            used_recovery = True
        except Exception:
            dek = None

    if dek is None:
        if has_recovery and not recovery_key:
            raise RecoveryKeyNeeded(
                "The passphrase did not open this archive. It was made with a printed "
                "recovery key — enter the recovery key from the sheet kept with the backup "
                "drive, or check the passphrase."
            )
        raise WrongPassphrase(
            "Archive did not open — the passphrase is wrong, the recovery key is wrong, "
            "or the file has been altered."
        )

    return _stream_decrypt(
        fin,
        dst,
        dek,
        raw_header,
        chunk_size,
        plaintext_len,
        nonce_prefix,
        sha,
        _SHA_OFFSET_V2,
        recovery_slot=used_recovery,
    )


def has_recovery_slot(path: os.PathLike | str) -> bool:
    """Whether the archive was written with a printed recovery key."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(HEADER_V2_LEN)
    except OSError:
        return False
    if not head.startswith(MAGIC_V2) or len(head) < HEADER_V2_LEN:
        return False
    flags = head[9]
    return bool(flags & FLAG_RECOVERY)


def verify_archive(
    path: os.PathLike | str,
    passphrase: str,
    *,
    recovery_key: Optional[str] = None,
) -> dict[str, Any]:
    """Full proof: decrypt, compare the digest, and CRC every entry in the zip.

    This is what the panel means when it says *verified*. Anything less is a hope.
    """
    with tempfile.TemporaryDirectory(prefix="centurion-verify-") as td:
        out = Path(td) / "verify.zip"
        stats = decrypt_file(path, out, passphrase, recovery_key=recovery_key)
        files = 0
        uncompressed = 0
        bad = None
        with zipfile.ZipFile(out, "r") as zf:
            bad = zf.testzip()
            for info in zf.infolist():
                files += 1
                uncompressed += info.file_size
        if bad is not None:
            raise BackupCryptoError(f"Archive contains a corrupt entry: {bad}")
        stats.update({"files": files, "uncompressed_bytes": uncompressed, "verified": True})
        return stats


def prompt_passphrase(*, confirm: bool, allow_stdin_fallback: bool = True) -> str:
    """Read a passphrase from a terminal, twice when creating one.

    An empty passphrase is refused rather than silently downgrading to a plain
    zip, because that is how a practice ends up with an unencrypted drive and a
    cheerful message saying the backup worked.
    """
    while True:
        first = getpass.getpass("Backup passphrase: " if not confirm else "Choose a backup passphrase: ")
        if not first:
            print("An empty passphrase is not encryption. Try again.", file=sys.stderr)
            if not allow_stdin_fallback or not sys.stdin.isatty():
                raise BackupCryptoError("No passphrase supplied.")
            continue
        if confirm:
            second = getpass.getpass("Again, to be sure: ")
            if first != second:
                print("Those did not match. Try again.", file=sys.stderr)
                continue
        return first


def read_passphrase_file(path: os.PathLike | str) -> str:
    value = Path(path).expanduser().read_text(encoding="utf-8").strip()
    if not value:
        raise BackupCryptoError(f"Passphrase file {path} is empty.")
    return value


def read_recovery_key_file(path: os.PathLike | str) -> str:
    value = Path(path).expanduser().read_text(encoding="utf-8").strip()
    if not value:
        raise BackupCryptoError(f"Recovery key file {path} is empty.")
    return value
