"""Bridge surface for the backup record.

Kept in its own module so the bridge dispatch stays a two-line change: the
machine's backup state is read by the desktop shell, the panel and the check-in,
and it must not be entangled with the rest of the bridge's surface.

⚠ THE INVARIANT: an unreadable record is not an empty one. A machine whose backup
ledger is missing or corrupt reports `readable: false` and `overdue: true`, and
the panel renders the em dash on that. It must never render as a fresh backup.
"""

from __future__ import annotations

from typing import Any, Dict


def backup_status_payload(request_id: str) -> Dict[str, Any]:
    """The backup record as a bridge response body."""
    try:
        from centurion_cli import backup_state as _bs

        st = _bs.status()
        return {
            "id": request_id,
            "ok": True,
            "action": "backup_status",
            "backup": st.to_dict(),
            "lines": _bs.human_status(),
            "checkin": _bs.checkin_fields(),
        }
    except Exception as exc:  # never let a backup read break the bridge
        return {
            "id": request_id,
            "ok": False,
            "action": "backup_status",
            "code": "BACKUP_STATUS_FAILED",
            "error": str(exc),
            "message": "Could not read this machine's backup record.",
            "retryable": True,
        }
