"""Backup state: the ledger, the overdue rule, and the reminder.

The invariant under test: an unreadable record is not an empty one. A missing
ledger must never render as a fresh backup, and a plain unverified zip must never
read as a safe one.
"""

from __future__ import annotations

import json
import time
from datetime import datetime
from pathlib import Path

import pytest

from centurion_cli import backup_state as bs


@pytest.fixture
def home(tmp_path) -> Path:
    (tmp_path / "state").mkdir()
    return tmp_path


def test_a_machine_with_no_ledger_has_no_backup_rather_than_a_fresh_one(home):
    st = bs.status(centurion_home=home)
    assert st.readable is False
    assert st.last_at is None
    assert st.overdue is True
    assert st.never is False  # never = readable and empty; unreadable is different


def test_an_empty_ledger_is_never_backed_up_and_overdue(home):
    bs.record_backup(path="/x", size_bytes=0, centurion_home=home)
    ledger = json.loads((home / "state" / "backup-ledger.json").read_text())
    ledger["entries"] = []
    (home / "state" / "backup-ledger.json").write_text(json.dumps(ledger))

    st = bs.status(centurion_home=home)
    assert st.readable is True
    assert st.never is True
    assert st.overdue is True


def test_a_corrupt_ledger_is_reported_not_repaired(home):
    (home / "state" / "backup-ledger.json").write_text("{not json")
    st = bs.status(centurion_home=home)
    assert st.readable is False
    assert st.error and "unreadable" in st.error
    assert st.last_at is None


def test_a_fresh_verified_backup_is_ok(home):
    bs.record_backup(path="/x/a.cbk", size_bytes=1000, records=2, verified=True, centurion_home=home)
    st = bs.status(centurion_home=home)
    assert st.readable and not st.never
    assert st.last_verified is True
    assert st.overdue is False
    assert st.next_due_at > st.last_at


def test_next_due_lands_on_the_scheduled_slot_not_seven_days_after_the_click(home):
    """A Saturday panic-backup must not move the practice's Wednesday routine."""
    saturday = datetime(2026, 11, 14, 9, 34).timestamp()
    bs.record_backup(path="/x/a.cbk", size_bytes=1, verified=True, at=saturday, centurion_home=home)
    st = bs.status(now=saturday, centurion_home=home)
    nxt = datetime.fromtimestamp(st.next_due_at)
    assert nxt.weekday() == 2, nxt.strftime("%A")
    assert (nxt.hour, nxt.minute) == (9, 0)


def test_fifteen_days_old_is_overdue(home):
    old = time.time() - 15 * 86400
    bs.record_backup(path="/x/a.cbk", size_bytes=1, verified=True, at=old, centurion_home=home)
    st = bs.status(centurion_home=home)
    assert st.age_days >= 14.9
    assert st.overdue is True


def test_thirteen_days_old_is_not_overdue(home):
    old = time.time() - 13 * 86400
    bs.record_backup(path="/x/a.cbk", size_bytes=1, verified=True, at=old, centurion_home=home)
    assert bs.status(centurion_home=home).overdue is False


def test_an_unverified_backup_is_overdue_even_when_recent(home):
    """A recent archive nobody proved is not cover."""
    bs.record_backup(path="/x/a.zip", size_bytes=1, verified=False, encrypted=False, centurion_home=home)
    st = bs.status(centurion_home=home)
    assert st.last_verified is False
    assert st.overdue is True


def test_entries_are_newest_first_and_capped(home):
    for i in range(5):
        bs.record_backup(path=f"/x/{i}.cbk", size_bytes=i, verified=True, at=1000 + i, centurion_home=home)
    st = bs.status(centurion_home=home)
    assert [e.path for e in st.entries][:2] == ["/x/4.cbk", "/x/3.cbk"]
    assert len(st.entries) <= bs.MAX_ENTRIES


def test_checkin_fields_are_metadata_only(home):
    bs.record_backup(path="/x/secret-client-archive.cbk", size_bytes=10, verified=True, centurion_home=home)
    fields = bs.checkin_fields(centurion_home=home)
    assert set(fields) == {"last_backup_at", "backup_verified", "backup_overdue"}
    assert fields["backup_verified"] is True
    assert "secret" not in json.dumps(fields)


def test_checkin_fields_claim_nothing_when_the_record_is_unreadable(home):
    fields = bs.checkin_fields(centurion_home=home)
    assert fields["last_backup_at"] is None
    assert fields["backup_verified"] is None
    assert fields["backup_overdue"] is None


def test_reminder_is_a_weekly_calendar_entry_with_no_secrets():
    ics = bs.reminder_ics(bs.BackupSchedule(weekday=2, time="09:00", drive="/media/practice-backup"))
    assert ics.startswith("BEGIN:VCALENDAR")
    assert "RRULE:FREQ=WEEKLY" in ics
    assert "BEGIN:VALARM" in ics
    # It may SAY the passphrase is the customer's; it must never carry one, and it
    # must not name the archive or the drive — a calendar syncs to phones.
    assert "PASS:" not in ics
    assert "/media/practice-backup" not in ics
    assert ".cbk" not in ics
    assert "\r\n" in ics


def test_next_slot_is_the_coming_chosen_weekday():
    # Wednesday 13 Nov 2026, 10:00 -> the 09:00 slot that week has passed, so next week.
    now = datetime(2026, 11, 13, 10, 0).timestamp()  # Friday
    st = bs.status(now=now, centurion_home=Path("/nonexistent-home"))
    nxt = datetime.fromtimestamp(st.next_due_at)
    assert nxt.weekday() == 2
    assert nxt.hour == 9
    assert nxt > datetime(2026, 11, 13, 10, 0)


def test_schedule_round_trips(home):
    bs.set_schedule(bs.BackupSchedule(weekday=4, time="18:30", drive="/mnt/usb"), centurion_home=home)
    st = bs.status(centurion_home=home)
    assert st.schedule.weekday == 4
    assert st.schedule.time == "18:30"
    assert st.schedule.drive == "/mnt/usb"
    assert "Friday 18:30" in st.schedule.label()


def test_human_status_says_never_rather_than_zero(home):
    lines = bs.human_status(centurion_home=home)
    joined = "\n".join(lines)
    assert "could not read" in joined
    assert "OVERDUE" in joined


def test_human_status_prints_dashes_not_zero_for_an_unreadable_record(home):
    (home / "state" / "backup-ledger.json").write_text("garbage")
    joined = "\n".join(bs.human_status(centurion_home=home))
    assert "—" in joined
    assert "0.0 days ago" not in joined
