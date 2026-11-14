"""Tests for the encrypted backup container.

The gate this file exists to hold: an archive that leaves the machine must be
encrypted, must refuse a wrong passphrase, must refuse a tampered byte, and must
prove itself before anyone calls it verified.
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


def test_round_trip_preserves_bytes(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"a.txt": b"client file\n" * 500, "b/db.sqlite": os.urandom(4096)})
    original = src.read_bytes()

    stats = bc.encrypt_file(src, tmp_path / "a.cbk", "correct horse battery staple")
    assert stats["plaintext_bytes"] == len(original)
    assert bc.is_encrypted(tmp_path / "a.cbk")

    back = bc.decrypt_file(tmp_path / "a.cbk", tmp_path / "out.zip", "correct horse battery staple")
    assert back["plaintext_bytes"] == len(original)
    assert (tmp_path / "out.zip").read_bytes() == original


def test_multi_chunk_round_trip(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"big.bin": os.urandom(50_000)})
    original = src.read_bytes()

    bc.encrypt_file(src, tmp_path / "b.cbk", "pw", chunk_size=4096)
    back = bc.decrypt_file(tmp_path / "b.cbk", tmp_path / "out.zip", "pw")
    assert back["records"] > 1
    assert (tmp_path / "out.zip").read_bytes() == original


def test_wrong_passphrase_is_refused(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"a.txt": b"secret"})
    bc.encrypt_file(src, tmp_path / "c.cbk", "right")

    with pytest.raises(bc.WrongPassphrase):
        bc.decrypt_file(tmp_path / "c.cbk", tmp_path / "out.zip", "wrong")
    assert not (tmp_path / "out.zip").exists(), "a failed decrypt must leave no partial file"


def test_tampered_archive_is_refused(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"a.txt": b"x" * 5000})
    target = tmp_path / "d.cbk"
    bc.encrypt_file(src, target, "pw")

    blob = bytearray(target.read_bytes())
    blob[bc.HEADER_LEN + 100] ^= 0xFF  # flip one byte of the first record
    target.write_bytes(bytes(blob))

    with pytest.raises(bc.WrongPassphrase):
        bc.decrypt_file(target, tmp_path / "out.zip", "pw")


def test_truncated_archive_is_refused(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"a.txt": b"y" * 5000})
    target = tmp_path / "e.cbk"
    bc.encrypt_file(src, target, "pw")
    target.write_bytes(target.read_bytes()[:-10])

    with pytest.raises(bc.WrongPassphrase):
        bc.decrypt_file(target, tmp_path / "out.zip", "pw")


def test_plain_zip_is_not_mistaken_for_a_container(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"a.txt": b"z"})
    assert bc.is_encrypted(src) is False
    with pytest.raises(bc.NotAnEncryptedArchive):
        bc.decrypt_file(src, tmp_path / "out.zip", "pw")


def test_empty_passphrase_is_refused(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"a.txt": b"z"})
    with pytest.raises(bc.BackupCryptoError):
        bc.encrypt_file(src, tmp_path / "f.cbk", "")


def test_verify_proves_the_archive(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"one.txt": b"1" * 100, "two.txt": b"2" * 200})
    target = tmp_path / "g.cbk"
    bc.encrypt_file(src, target, "pw")

    stats = bc.verify_archive(target, "pw")
    assert stats["verified"] is True
    assert stats["files"] == 2
    assert stats["uncompressed_bytes"] == 300


def test_verify_refuses_a_wrong_passphrase(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"one.txt": b"1"})
    target = tmp_path / "h.cbk"
    bc.encrypt_file(src, target, "pw")
    with pytest.raises(bc.WrongPassphrase):
        bc.verify_archive(target, "not-the-password")


def test_remove_source_only_after_success(tmp_path):
    src = tmp_path / "archive.zip"
    _make_zip(src, {"one.txt": b"1"})
    target = tmp_path / "i.cbk"
    bc.encrypt_file(src, target, "pw", remove_source=True)
    assert not src.exists()
    assert bc.is_encrypted(target)


def test_header_has_no_plaintext_filenames(tmp_path):
    """A backup on a USB drive must not leak the practice's client names."""
    secret_name = "clients/harold-and-sons-ltd/vat-return.txt"
    src = tmp_path / "archive.zip"
    _make_zip(src, {secret_name: b"figures"})
    target = tmp_path / "j.cbk"
    bc.encrypt_file(src, target, "pw")

    blob = target.read_bytes()
    assert b"harold" not in blob.lower()
    assert b"clients/" not in blob
