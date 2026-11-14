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

CONTAINER FORMAT  (`.cbk`)
--------------------------
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
KDF_SCRYPT = 1
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


def is_encrypted(path: os.PathLike | str) -> bool:
    """True when the file starts with our magic. Never raises on a short file."""
    try:
        with open(path, "rb") as fh:
            return fh.read(len(MAGIC)) == MAGIC
    except OSError:
        return False


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

    if not passphrase:
        raise BackupCryptoError("A passphrase is required. An empty passphrase is not encryption.")
    kdf = Scrypt(salt=salt, length=_KEY_LEN, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P)
    return kdf.derive(passphrase.encode("utf-8"))


def _aad(header: bytes, counter: int) -> bytes:
    """Bind each record to the header — but only its immutable part.

    The trailing SHA-256 is filled in AFTER the plaintext has been streamed, so
    it cannot take part in the authentication of records written before it is
    known. Excluding it is what makes encrypt and decrypt agree on the AAD.
    """
    return header[:_SHA_OFFSET] + counter.to_bytes(8, "big")


def _nonce(prefix: bytes, counter: int) -> bytes:
    return prefix + counter.to_bytes(8, "big")


def encrypt_file(
    src: os.PathLike | str,
    dst: os.PathLike | str,
    passphrase: str,
    *,
    chunk_size: int = _DEFAULT_CHUNK,
    remove_source: bool = False,
) -> dict[str, Any]:
    """Encrypt `src` into a `.cbk` container at `dst`. Returns stats.

    The plaintext digest is computed during the pass and written back into the
    header at the end, so verification needs no second read of the source.
    """
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    src, dst = Path(src), Path(dst)
    salt = os.urandom(_SALT_LEN)
    nonce_prefix = os.urandom(_NONCE_PREFIX_LEN)
    plaintext_len = src.stat().st_size
    header = HEADER_STRUCT.pack(
        MAGIC, KDF_SCRYPT, salt, chunk_size, plaintext_len, int.from_bytes(nonce_prefix, "big"), b"\x00" * 32
    )
    key = _derive_key(passphrase, salt)
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
                ct = aead.encrypt(_nonce( nonce_prefix, counter), block, _aad(header, counter))
                fout.write(ct)
                written += len(block)
                counter += 1
            # Fill the digest in now that the whole plaintext has been read.
            fout.seek(_SHA_OFFSET)
            fout.write(digest.digest())
            fout.flush()
            os.fsync(fout.fileno())
        os.replace(tmp_dst, dst)
    except Exception:
        tmp_dst.unlink(missing_ok=True)
        raise

    if remove_source:
        src.unlink(missing_ok=True)

    return {
        "archive": str(dst),
        "plaintext_bytes": written,
        "archive_bytes": dst.stat().st_size,
        "records": counter,
        "sha256": digest.hexdigest(),
    }


def decrypt_file(
    src: os.PathLike | str,
    dst: os.PathLike | str,
    passphrase: str,
    *,
    expect_sha256: Optional[str] = None,
) -> dict[str, Any]:
    """Decrypt a `.cbk` container to `dst`. Raises WrongPassphrase on failure."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    src, dst = Path(src), Path(dst)
    with open(src, "rb") as fin:
        raw_header = fin.read(HEADER_LEN)
        if len(raw_header) != HEADER_LEN:
            raise NotAnEncryptedArchive("File is too short to be a Centurion backup container.")
        magic, kdf_id, salt, chunk_size, plaintext_len, nonce_seed, sha = HEADER_STRUCT.unpack(raw_header)
        if magic != MAGIC:
            raise NotAnEncryptedArchive("Not an encrypted Centurion backup (no container magic).")
        if kdf_id != KDF_SCRYPT:
            raise BackupCryptoError(f"Unsupported key-derivation id {kdf_id}.")
        if chunk_size <= 0 or chunk_size > 64 * 1024 * 1024:
            raise BackupCryptoError(f"Refusing implausible chunk size {chunk_size}.")

        nonce_prefix = nonce_seed.to_bytes(_NONCE_PREFIX_LEN, "big")
        aead = AESGCM(_derive_key(passphrase, salt))

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
                            _nonce(nonce_prefix, counter), blob, _aad(raw_header, counter)
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
    if expect_sha256 and expect_sha256.lower() != actual.hex():
        Path(dst).unlink(missing_ok=True)
        raise BackupCryptoError("Archive digest does not match the expected value.")

    return {
        "zip": str(dst),
        "plaintext_bytes": plaintext_len,
        "records": counter,
        "sha256": actual.hex(),
    }


def verify_archive(path: os.PathLike | str, passphrase: str) -> dict[str, Any]:
    """Full proof: decrypt, compare the digest, and CRC every entry in the zip.

    This is what the panel means when it says *verified*. Anything less is a hope.
    """
    with tempfile.TemporaryDirectory(prefix="centurion-verify-") as td:
        out = Path(td) / "verify.zip"
        stats = decrypt_file(path, out, passphrase)
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
