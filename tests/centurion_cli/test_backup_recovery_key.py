"""Tests for the printed recovery key — Editions §6.3, the last blocker on item 6.

The gate this file exists to hold, in the plan's own words:

    "A recovery key, printed once, for the safe. Losing the passphrase must be a
    recoverable mistake for a business, and unrecoverable for us."

So the tests are about what must be TRUE of a business-recoverable archive:
either credential opens it, neither credential alone is enough to weaken it, a
v1 archive still opens unchanged, and a customer who types the wrong one is told
to go and get the sheet rather than told their passphrase is wrong.
"""

from __future__ import annotations

import os
import zipfile
from pathlib import Path

import pytest

from centurion_cli import backup_crypto as bc


def _make_zip(path: Path, payloads: dict[str, bytes]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in payloads.items():
            zf.writestr(name, data)
    return path


@pytest.fixture
def src(tmp_path):
    p = tmp_path / "archive.zip"
    _make_zip(p, {"clients/acme.txt": b"signed engagement letter\n" * 200})
    return p


PASS = "correct horse battery staple"
REC = "K7QX-4M2P-9WTA-3B6N-8RVD-5HZE-2J4C-6YUG"


def test_recovery_key_round_trip_with_passphrase(tmp_path, src):
    original = src.read_bytes()
    stats = bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)

    assert stats["container"] == "v2"
    assert stats["recovery_key_present"] is True
    assert bc.has_recovery_slot(tmp_path / "a.cbk")

    back = bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", PASS)
    assert (tmp_path / "out.zip").read_bytes() == original
    assert back["recovery_slot"] is False


def test_fogotten_passphrase_is_opened_by_the_printed_key(tmp_path, src):
    """The whole point: the practice lost the passphrase, not the archive."""
    original = src.read_bytes()
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)

    back = bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", "", recovery_key=REC)
    assert (tmp_path / "out.zip").read_bytes() == original
    assert back["recovery_slot"] is True


def test_recovery_key_is_accepted_however_it_is_typed(tmp_path, src):
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    typed = "k7qx 4m2p9wta 3b6n8rvd5hze2j4c6yug"  # lower case, spaces, no dashes
    back = bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out2.zip", "", recovery_key=typed)
    assert back["recovery_slot"] is True


def test_no_credentials_says_get_the_sheet_not_wrong_passphrase(tmp_path, src):
    """A wrong instruction here is the sentence that loses a practice's data."""
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    with pytest.raises(bc.RecoveryKeyNeeded) as exc:
        bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", "the wrong one")
    msg = str(exc.value)
    assert "recovery key" in msg.lower()
    assert not (tmp_path / "out.zip").exists()
    assert not (tmp_path / "out.part").exists()


def test_wrong_passphrase_and_wrong_key_is_refused(tmp_path, src):
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    with pytest.raises(bc.WrongPassphrase):
        bc.decrypt_file(
            tmp_path / "a.cbk",
            tmp_path / "out.zip",
            "wrong",
            recovery_key="AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH",
        )
    assert not (tmp_path / "out.zip").exists()


def test_recovery_key_does_not_open_a_v1_archive(tmp_path, src):
    """v1 has no wrap block, so no key can recover it — said plainly, not silently."""
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS)  # no recovery key → v1
    assert bc.has_recovery_slot(tmp_path / "a.cbk") is False
    with pytest.raises(bc.BackupCryptoError) as exc:
        bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", "", recovery_key=REC)
    # The message must send them to the passphrase, not to a recovery key that
    # does not exist for this archive.
    assert "recovery key" in str(exc.value).lower()
    assert "passphrase is the only way in" in str(exc.value)


def test_v1_archive_still_opens_unchanged(tmp_path, src):
    """Archives already in customers' drawers must open in every future release."""
    original = src.read_bytes()
    stats = bc.encrypt_file(src, tmp_path / "a.cbk", PASS)
    assert stats["container"] == "v1"
    assert stats["recovery_key_present"] is False
    assert (tmp_path / "a.cbk").read_bytes()[:8] == bc.MAGIC
    bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", PASS)
    assert (tmp_path / "out.zip").read_bytes() == original


def test_tampered_v2_archive_is_refused(tmp_path, src):
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    raw = bytearray((tmp_path / "a.cbk").read_bytes())
    raw[-5] ^= 0xFF
    (tmp_path / "a.cbk").write_bytes(bytes(raw))
    with pytest.raises(bc.WrongPassphrase):
        bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", PASS, recovery_key=REC)


def test_swapping_a_recovery_wrap_for_a_passphrase_wrap_is_refused(tmp_path, src):
    """The two wraps are bound to their own slots by distinct AAD."""
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    raw = bytearray((tmp_path / "a.cbk").read_bytes())
    # pass_wrap occupies header bytes 74..122; rec_wrap 162..210
    pass_wrap = bytes(raw[74:122])
    raw[162:210] = pass_wrap
    (tmp_path / "a.cbk").write_bytes(bytes(raw))
    with pytest.raises(bc.WrongPassphrase):
        bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", "", recovery_key=REC)


def test_verify_proves_a_v2_archive_with_either_credential(tmp_path, src):
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    by_pass = bc.verify_archive(tmp_path / "a.cbk", PASS)
    assert by_pass["verified"] is True and by_pass["files"] == 1

    by_key = bc.verify_archive(tmp_path / "a.cbk", "", recovery_key=REC)
    assert by_key["verified"] is True
    assert by_key["recovery_slot"] is True
    assert by_key["sha256"] == by_pass["sha256"]


def test_v2_header_carries_no_plaintext_identifiers(tmp_path, src):
    """Same promise as v1: a drive in a drawer names nobody."""
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC)
    blob = (tmp_path / "a.cbk").read_bytes()
    for needle in (b"clients", b"acme", b"engagement", PASS.encode(), REC.encode()):
        assert needle not in blob


def test_remove_source_only_after_success(tmp_path, src):
    bc.encrypt_file(src, tmp_path / "a.cbk", PASS, recovery_key=REC, remove_source=True)
    assert not src.exists()
    assert (tmp_path / "a.cbk").exists()


def test_generated_recovery_keys_are_unguessable_and_printable():
    keys = {bc.generate_recovery_key() for _ in range(50)}
    assert len(keys) == 50
    for key in keys:
        assert len(key.replace("-", "")) == 32
        assert all(ch.isalnum() for ch in key.replace("-", ""))
        # Crockford's alphabet — I, L, O and U are absent by construction, so a
        # key read down a telephone cannot become a different key.
        assert not (set(key.replace("-", "")) & set("ILOU"))


def test_confusable_characters_are_folded_on_entry():
    """O for zero, I and L for one, U for V — the slips a human actually makes."""
    base = "K7QX-4M2P-9WTA-3B6N-8RVD-5HZE-2J4C-6YUG"
    assert bc.normalise_recovery_key(base) == bc.normalise_recovery_key(
        base.lower().replace("-", " ")
    )
    assert bc.normalise_recovery_key("OILU") == "011V"


def test_normalise_refuses_an_empty_recovery_key():
    with pytest.raises(bc.BackupCryptoError):
        bc.normalise_recovery_key("  --  ")


def test_empty_passphrase_is_still_refused_with_a_recovery_key(tmp_path, src):
    with pytest.raises(bc.BackupCryptoError):
        bc.encrypt_file(src, tmp_path / "a.cbk", "", recovery_key=REC)


# ── one key per machine, not one per archive ─────────────────────────────────
# If a fresh key were minted on every backup, the sheet in the safe would be
# useless by the second week. The key must be created once and reused.


def test_machine_recovery_key_is_created_once_and_reused(tmp_path):
    from centurion_cli import backup as bk

    first, created = bk._machine_recovery_key(tmp_path)
    assert created is True
    assert len(first.replace("-", "")) == 32

    second, created_again = bk._machine_recovery_key(tmp_path)
    assert created_again is False
    assert second == first

    path = tmp_path / "backup" / bk.RECOVERY_KEY_FILENAME
    assert path.read_text(encoding="utf-8").strip() == first
    assert oct(path.stat().st_mode)[-3:] == "600"


def test_a_later_archive_opens_with_the_same_machine_key(tmp_path, src):
    """Two archives, one sheet: the property the practice actually relies on."""
    from centurion_cli import backup as bk

    key, _ = bk._machine_recovery_key(tmp_path)
    bc.encrypt_file(src, tmp_path / "week1.cbk", PASS, recovery_key=key)
    bc.encrypt_file(src, tmp_path / "week2.cbk", "a completely different passphrase", recovery_key=key)

    for name in ("week1.cbk", "week2.cbk"):
        back = bc.decrypt_file(tmp_path / name, tmp_path / f"{name}.zip", "", recovery_key=key)
        assert back["recovery_slot"] is True
