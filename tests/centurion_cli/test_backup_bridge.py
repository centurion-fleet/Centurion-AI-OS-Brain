"""The backup surface the panel, the desktop shell and the fleet view read.

Three things must hold:
  1. the bridge action answers with the record and never raises;
  2. a machine with no readable record says so, and says OVERDUE;
  3. the licence check-in carries backup metadata only — never a path or a name.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import pytest

from centurion_cli import backup_bridge, backup_state as bs


@pytest.fixture
def home(tmp_path, monkeypatch):
    (tmp_path / "state").mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    return tmp_path


def test_bridge_reports_a_machine_that_has_never_backed_up(home):
    payload = backup_bridge.backup_status_payload("req-1")

    assert payload["ok"] is True
    assert payload["action"] == "backup_status"
    assert payload["backup"]["readable"] is False
    assert payload["backup"]["last_at"] is None
    assert payload["backup"]["overdue"] is True
    assert any("could not read" in line for line in payload["lines"])


def test_bridge_reports_ok_after_a_verified_backup(home):
    bs.record_backup(path="/media/usb/a.cbk", size_bytes=4096, records=3, verified=True, centurion_home=home)
    payload = backup_bridge.backup_status_payload("req-2")

    assert payload["backup"]["readable"] is True
    assert payload["backup"]["last_verified"] is True
    assert payload["backup"]["overdue"] is False
    assert payload["backup"]["count"] == 1
    assert "OK" in " ".join(payload["lines"])


def test_bridge_never_leaks_the_archive_path_into_the_checkin_block(home):
    bs.record_backup(
        path="/media/usb/CLIENT-NAMES-HERE.cbk", size_bytes=1, verified=True, centurion_home=home
    )
    payload = backup_bridge.backup_status_payload("req-3")

    assert set(payload["checkin"]) == {"last_backup_at", "backup_verified", "backup_overdue"}
    assert "CLIENT-NAMES" not in json.dumps(payload["checkin"])


def test_bridge_returns_ok_false_rather_than_raising(monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("ledger unreadable")

    monkeypatch.setattr(bs, "status", boom)
    payload = backup_bridge.backup_status_payload("req-4")

    assert payload["ok"] is False
    assert payload["code"] == "BACKUP_STATUS_FAILED"
    assert payload["retryable"] is True


def test_an_unverified_archive_is_overdue_on_the_panel(home):
    bs.record_backup(path="/tmp/plain.zip", size_bytes=1, verified=False, encrypted=False, centurion_home=home)
    payload = backup_bridge.backup_status_payload("req-5")
    assert payload["backup"]["overdue"] is True
    assert payload["checkin"]["backup_overdue"] is True


def test_the_checkin_helper_degrades_to_nulls_not_to_optimism(monkeypatch):
    # NOTE: `from centurion.license import phone_home` yields the FUNCTION of that
    # name, not the module — the package re-exports it. Go through importlib.
    import importlib

    phone_home = importlib.import_module("centurion.license.phone_home")

    monkeypatch.setattr(bs, "checkin_fields", lambda **k: (_ for _ in ()).throw(RuntimeError("nope")))
    fields = phone_home._backup_checkin_fields()
    assert fields == {"last_backup_at": None, "backup_verified": None, "backup_overdue": None}


def test_the_checkin_helper_passes_real_state_through(home):
    import importlib

    phone_home = importlib.import_module("centurion.license.phone_home")

    bs.record_backup(path="/x/a.cbk", size_bytes=1, verified=True, centurion_home=home)
    fields = phone_home._backup_checkin_fields()
    assert fields["backup_verified"] is True
    assert fields["backup_overdue"] is False
    assert fields["last_backup_at"] and fields["last_backup_at"] <= int(time.time())
