"""A machine that holds client records does not write a plaintext archive.

The rule (business/EDITIONS.md §6.3): an unencrypted zip of a UK practice's
client files on a USB stick in a drawer is a UK GDPR problem that surfaces after
a burglary, not before. So the refusal lives in the command rather than in an
operator's memory, and it happens **before** anything is written — a refused run
must not leave a half-artefact that somebody later mistakes for a backup.

The rotation rule is the other half: the last eight scheduled archives, oldest
overwritten. It must only ever delete containers this command named itself.
"""

from __future__ import annotations

import types
from pathlib import Path

import pytest

from centurion_cli import backup as bk


@pytest.fixture
def home(tmp_path, monkeypatch):
    (tmp_path / "state").mkdir()
    (tmp_path / "config.yaml").write_text("display:\n  language: en\n", encoding="utf-8")
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    # Keep the backup record out of the shared state dir under test.
    monkeypatch.setattr(bk._bs, "record_backup", lambda **kw: None)
    return tmp_path


def _args(**over):
    base = dict(
        output=None,
        quick=False,
        label=None,
        encrypt=False,
        passphrase_file=None,
        status=False,
        reminder=None,
        force=False,
    )
    base.update(over)
    return types.SimpleNamespace(**base)


def _edition(monkeypatch, tier: str):
    """Pretend the licence says `tier` without needing a licence server."""
    fake = types.SimpleNamespace(tier=tier)
    monkeypatch.setattr(bk, "_carries_client_records", lambda: bk_truth(tier))


def bk_truth(tier: str):
    labels = {
        "brain": "Centurion Brain",
        "accountant": "Centurion Accountant Brain",
        "practice": "Centurion Accountant Practice",
        "association": "Centurion Association Brain",
    }
    return (tier in bk._CLIENT_RECORD_TIERS, labels.get(tier, "Centurion Brain"))


@pytest.mark.parametrize("tier", ["accountant", "practice", "association"])
def test_client_machines_refuse_a_plaintext_archive(home, monkeypatch, capsys, tier):
    monkeypatch.setattr(bk, "_carries_client_records", lambda: bk_truth(tier))

    with pytest.raises(SystemExit) as exc:
        bk.run_backup(_args(output=str(home / "plain.zip")))

    assert exc.value.code == 2
    out = capsys.readouterr().out
    assert "Refused" in out
    assert bk_truth(tier)[1] in out
    assert "Nothing was written" in out
    # The whole point: no artefact, not a small one.
    assert not (home / "plain.zip").exists()
    assert list(home.glob("*.zip")) == []


def test_the_brain_still_writes_a_plain_archive(home, monkeypatch):
    """A personal Brain is a different product and keeps its present behaviour."""
    monkeypatch.setattr(bk, "_carries_client_records", lambda: bk_truth("brain"))

    bk.run_backup(_args(output=str(home / "brain.zip")))
    assert (home / "brain.zip").is_file()


def test_an_unreadable_edition_does_not_block_backups(home, monkeypatch, capsys):
    """Fail open, and say which way it failed.

    Refusing backups on every fresh install is how a safety rule gets switched
    off by the person it was meant to protect.
    """
    def boom():
        raise RuntimeError("no licence record")
    # Mirror the real helper's own except-branch behaviour.
    import centurion.license.edition as ed  # noqa: F401  (import must work)

    monkeypatch.setattr(ed, "current_edition", boom)
    carries, label = bk._carries_client_records()
    assert carries is False
    assert label == "Centurion Brain"


def test_rotation_keeps_the_last_eight_and_leaves_hand_named_files_alone(tmp_path):
    for i in range(11):
        p = tmp_path / f"centurion-backup-2026-11-{i:02d}-090000.cbk"
        p.write_bytes(b"x")
        # Distinct mtimes so "newest eight" is deterministic.
        import os
        os.utime(p, (1_700_000_000 + i, 1_700_000_000 + i))
    hand_named = tmp_path / "practice-only-copy.cbk"
    hand_named.write_bytes(b"precious")

    removed = bk._prune_container_rotation(tmp_path)

    survivors = sorted(p.name for p in tmp_path.glob("centurion-backup-*.cbk"))
    assert len(survivors) == bk.CONTAINER_ROTATION_KEEP
    assert len(removed) == 3
    # oldest three went, the newest eight stayed
    assert not (tmp_path / "centurion-backup-2026-11-00-090000.cbk").exists()
    assert (tmp_path / "centurion-backup-2026-11-10-090000.cbk").exists()
    # a file we did not create is never deleted
    assert hand_named.is_file()


def test_rotation_is_a_no_op_below_the_threshold(tmp_path):
    p = tmp_path / "centurion-backup-2026-11-14-090000.cbk"
    p.write_bytes(b"x")
    assert bk._prune_container_rotation(tmp_path) == []
    assert p.is_file()
