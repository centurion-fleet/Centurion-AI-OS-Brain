"""Backup state: the ledger, the schedule, the overdue rule, and the reminder.

WHY THIS EXISTS
---------------
An encrypted archive is only half the promise. The other half is that a practice
actually takes one, every week, and that the machine can tell — before the phone
call — whether it has.

So every successful backup writes one line to a ledger, and everything else reads
from that ledger:

  * the machine's own front page, which says when the last verified backup was;
  * the reminder in the practice's calendar, which is generated from the schedule
    rather than typed by anyone;
  * the `last_backup_at` field in the licensing check-in, so the fleet view can
    show who has not backed up in a fortnight.

THE INVARIANT THIS FILE HOLDS
-----------------------------
**An unreadable record is not an empty one.** A missing or corrupt ledger means
*"no backup has ever been recorded"*, never *"0 days since the last backup"*. A
panel that renders a missing ledger as a fresh backup is worse than no panel: it
tells a principal he is covered on the morning he is not.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

LEDGER_VERSION = 1
LEDGER_RELPATH = Path("state") / "backup-ledger.json"

#: A verified backup older than this shows on the front page. Fourteen days is
#: one missed week plus a week of grace — long enough not to nag a practice that
#: shifted its routine by a day, short enough that the loss is never a month deep.
OVERDUE_AFTER_DAYS = 14

#: How many ledger entries to keep. The drive rotates eight archives; the record
#: of them is cheap, but an unbounded list in a JSON file is a slow problem.
MAX_ENTRIES = 64

WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")


# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------

@dataclass
class BackupEntry:
    at: float                      # epoch seconds, UTC
    path: str = ""
    bytes: int = 0
    records: int = 0
    verified: bool = False
    kind: str = "full"             # "full" | "quick"
    encrypted: bool = True

    def to_dict(self) -> Dict[str, Any]:
        return {
            "at": self.at,
            "path": self.path,
            "bytes": self.bytes,
            "records": self.records,
            "verified": self.verified,
            "kind": self.kind,
            "encrypted": self.encrypted,
        }


@dataclass
class BackupSchedule:
    """The customer's weekly slot. Weekly is the product default and the only one
    the panel offers — a monthly backup of a working practice loses too much."""
    weekday: int = 2               # Wednesday, Monday=0
    time: str = "09:00"
    drive: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {"weekday": self.weekday, "time": self.time, "drive": self.drive}

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BackupSchedule":
        try:
            weekday = int(data.get("weekday", 2))
        except (TypeError, ValueError):
            weekday = 2
        return cls(
            weekday=max(0, min(6, weekday)),
            time=str(data.get("time") or "09:00"),
            drive=str(data.get("drive") or ""),
        )

    def label(self) -> str:
        return f"weekly, {WEEKDAYS[self.weekday]} {self.time}"


def ledger_path(centurion_home: Optional[Path] = None) -> Path:
    if centurion_home is None:
        from centurion_constants import get_centurion_home

        centurion_home = get_centurion_home()
    return Path(centurion_home) / LEDGER_RELPATH


def read_ledger(centurion_home: Optional[Path] = None) -> Dict[str, Any]:
    """Read the ledger. Returns a dict with `ok` and `error`, never raises.

    A corrupt ledger is reported, not repaired silently — the same rule as the
    dashboard's unreadable-is-not-empty invariant.
    """
    path = ledger_path(centurion_home)
    if not path.is_file():
        return {"ok": False, "error": "missing", "entries": [], "schedule": BackupSchedule()}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return {"ok": False, "error": f"unreadable: {exc}", "entries": [], "schedule": BackupSchedule()}
    if not isinstance(raw, dict) or not isinstance(raw.get("entries", []), list):
        return {"ok": False, "error": "malformed", "entries": [], "schedule": BackupSchedule()}
    entries: List[BackupEntry] = []
    for item in raw.get("entries", []):
        if not isinstance(item, dict) or "at" not in item:
            continue
        try:
            entries.append(
                BackupEntry(
                    at=float(item["at"]),
                    path=str(item.get("path") or ""),
                    bytes=int(item.get("bytes") or 0),
                    records=int(item.get("records") or 0),
                    verified=bool(item.get("verified")),
                    kind=str(item.get("kind") or "full"),
                    encrypted=bool(item.get("encrypted", True)),
                )
            )
        except (TypeError, ValueError):
            continue
    entries.sort(key=lambda e: e.at, reverse=True)
    return {
        "ok": True,
        "error": None,
        "entries": entries[:MAX_ENTRIES],
        "schedule": BackupSchedule.from_dict(raw.get("schedule") or {}),
    }


def record_backup(
    *,
    path: str,
    size_bytes: int,
    records: int = 0,
    verified: bool = False,
    kind: str = "full",
    encrypted: bool = True,
    at: Optional[float] = None,
    centurion_home: Optional[Path] = None,
) -> BackupEntry:
    """Append one successful backup to the ledger. Atomic write, 0600."""
    state = read_ledger(centurion_home)
    entry = BackupEntry(
        at=float(at if at is not None else time.time()),
        path=str(path),
        bytes=int(size_bytes),
        records=int(records),
        verified=bool(verified),
        kind=kind,
        encrypted=bool(encrypted),
    )
    entries = [entry.to_dict()] + [e.to_dict() for e in state["entries"]]
    payload = {
        "version": LEDGER_VERSION,
        "schedule": state["schedule"].to_dict(),
        "entries": entries[:MAX_ENTRIES],
    }
    target = ledger_path(centurion_home)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".json.part")
    tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, target)
    return entry


def set_schedule(schedule: BackupSchedule, centurion_home: Optional[Path] = None) -> BackupSchedule:
    state = read_ledger(centurion_home)
    payload = {
        "version": LEDGER_VERSION,
        "schedule": schedule.to_dict(),
        "entries": [e.to_dict() for e in state["entries"]],
    }
    target = ledger_path(centurion_home)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".json.part")
    tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    os.replace(tmp, target)
    return schedule


# ---------------------------------------------------------------------------
# Status — what the panel and the check-in read
# ---------------------------------------------------------------------------

@dataclass
class BackupStatus:
    #: None means "we could not read the record" — NOT zero. Render as an em dash.
    last_at: Optional[float] = None
    last_verified: bool = False
    age_days: Optional[float] = None
    next_due_at: Optional[float] = None
    overdue: bool = False
    schedule: BackupSchedule = field(default_factory=BackupSchedule)
    entries: List[BackupEntry] = field(default_factory=list)
    readable: bool = True
    error: Optional[str] = None
    never: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "readable": self.readable,
            "error": self.error,
            "never": self.never,
            "last_at": self.last_at,
            "last_verified": self.last_verified,
            "age_days": None if self.age_days is None else round(self.age_days, 1),
            "next_due_at": self.next_due_at,
            "overdue": self.overdue,
            "schedule": self.schedule.to_dict(),
            "schedule_label": self.schedule.label(),
            "count": len(self.entries),
        }


def _next_occurrence(schedule: BackupSchedule, after: datetime) -> datetime:
    """The next weekly slot at or after `after` (local time, naive)."""
    try:
        hh, mm = (int(p) for p in schedule.time.split(":", 1))
    except (ValueError, AttributeError):
        hh, mm = 9, 0
    hh, mm = max(0, min(23, hh)), max(0, min(59, mm))
    days_ahead = (schedule.weekday - after.weekday()) % 7
    candidate = (after + timedelta(days=days_ahead)).replace(hour=hh, minute=mm, second=0, microsecond=0)
    if candidate <= after:
        candidate += timedelta(days=7)
    return candidate


def status(now: Optional[float] = None, centurion_home: Optional[Path] = None) -> BackupStatus:
    state = read_ledger(centurion_home)
    st = BackupStatus(schedule=state["schedule"], entries=state["entries"])
    now_dt = datetime.fromtimestamp(now if now is not None else time.time())

    if not state["ok"]:
        st.readable = False
        st.error = state["error"]
        # Unreadable is not empty and it is certainly not safe: a machine whose
        # backup record cannot be read must present as UNPROTECTED, never as OK.
        st.overdue = True
        # Still offer the next slot, but claim nothing about the last.
        st.next_due_at = _next_occurrence(st.schedule, now_dt).timestamp()
        return st

    if not st.entries:
        st.never = True
        st.next_due_at = _next_occurrence(st.schedule, now_dt).timestamp()
        st.overdue = True  # a machine with no backup at all is overdue by definition
        return st

    latest = st.entries[0]
    st.last_at = latest.at
    st.last_verified = latest.verified
    st.age_days = max(0.0, ((now if now is not None else time.time()) - latest.at) / 86400.0)
    # The next slot is the schedule's, not "seven days after whenever they last
    # pressed the button" — otherwise a Tuesday backup moves the practice's whole
    # routine and the calendar entry stops matching what the panel says.
    st.next_due_at = _next_occurrence(st.schedule, datetime.fromtimestamp(latest.at)).timestamp()
    st.overdue = st.age_days > OVERDUE_AFTER_DAYS or not latest.verified
    return st


def checkin_fields(now: Optional[float] = None, centurion_home: Optional[Path] = None) -> Dict[str, Any]:
    """The three fields to add to the licensing check-in payload.

    Metadata about the backup, never its contents: the fleet view needs to know
    who has not backed up, not what is in the archive.
    """
    st = status(now=now, centurion_home=centurion_home)
    return {
        "last_backup_at": int(st.last_at) if st.last_at else None,
        "backup_verified": bool(st.last_verified) if st.last_at else None,
        "backup_overdue": bool(st.overdue) if st.readable else None,
    }


# ---------------------------------------------------------------------------
# The reminder — a calendar entry the practice actually looks at
# ---------------------------------------------------------------------------

def reminder_ics(
    schedule: Optional[BackupSchedule] = None,
    *,
    now: Optional[float] = None,
    title: str = "Centurion backup — plug in the drive and press Back up",
) -> str:
    """A weekly recurring VEVENT for the practice's own calendar.

    The reminder lives in the diary the principal already looks at rather than in
    a notification that gets dismissed. It carries no passphrase and no path to
    anything sensitive — a calendar entry is synchronised to phones and servers.
    """
    schedule = schedule or BackupSchedule()
    now_dt = datetime.fromtimestamp(now if now is not None else time.time())
    start = _next_occurrence(schedule, now_dt)
    end = start + timedelta(minutes=15)
    stamp = now_dt.strftime("%Y%m%dT%H%M%SZ")

    def dt(value: datetime) -> str:
        # Floating local time on purpose: the slot is 9am wherever the practice is.
        return value.strftime("%Y%m%dT%H%M%S")

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Centurion AI//Backup Reminder//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        f"UID:centurion-backup-{int(now_dt.timestamp())}@centurion.local",
        f"DTSTAMP:{stamp}",
        f"DTSTART:{dt(start)}",
        f"DTEND:{dt(end)}",
        "RRULE:FREQ=WEEKLY",
        f"SUMMARY:{title}",
        "DESCRIPTION:Connect the backup drive and open the Centurion Backup panel. "
        "Choose the drive\\, press Back up now\\, wait for Verified. "
        "The passphrase is yours — Centurion does not hold a copy and cannot recover it.",
        "BEGIN:VALARM",
        "TRIGGER:-PT30M",
        "ACTION:DISPLAY",
        f"DESCRIPTION:{title}",
        "END:VALARM",
        "END:VEVENT",
        "END:VCALENDAR",
    ]
    return "\r\n".join(lines) + "\r\n"


def human_status(now: Optional[float] = None, centurion_home: Optional[Path] = None) -> List[str]:
    """Lines for the CLI. Deliberately states the difference between never and
    unreadable, and never prints a reassuring zero it cannot substantiate."""
    st = status(now=now, centurion_home=centurion_home)
    out: List[str] = []
    if not st.readable:
        out.append(f"Last backup:   — could not read the backup record ({st.error})")
        out.append("               Treat this machine as having no verified backup.")
    elif st.never:
        out.append("Last backup:   none recorded — this machine has never been backed up")
    else:
        when = datetime.fromtimestamp(st.last_at or 0.0).strftime("%Y-%m-%d %H:%M")
        age = f"{st.age_days:.1f} days ago" if st.age_days is not None else "unknown age"
        proof = "verified" if st.last_verified else "NOT verified"
        out.append(f"Last backup:   {when} ({age}) — {proof}")
        out.append(f"Archive:       {st.entries[0].path}")
    if st.next_due_at:
        nxt = datetime.fromtimestamp(st.next_due_at).strftime("%A %d %B, %H:%M")
        out.append(f"Next due:      {nxt}")
    out.append(f"Schedule:      {st.schedule.label()}" + (f" → {st.schedule.drive}" if st.schedule.drive else ""))
    if st.overdue:
        why = "no verified backup on record" if (st.never or not st.readable) else f"{st.age_days:.0f} days since the last one"
        out.append(f"STATE:         OVERDUE — {why}")
    else:
        out.append("STATE:         OK")
    return out
