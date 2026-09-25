"""The fleet inbox — where a message from another Centurion actually lands.

Until now there was no inbox. `_handle_fleet_message` accepted a message, looked
for a transport that is never constructed, fell back to a log line and returned
``{"status": "received"}``. The sender was told the message had been delivered;
it had been discarded. Nothing ever read it back, and no human could see it.

This module is deliberately small and dull: one JSON file per message, written
atomically, read back in order. It is the thing the "received" claim can point
at.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

_INBOX_DIRNAME = "messages"
_MAX_BODY_CHARS = 200_000


def _home() -> Path:
    base = os.environ.get("CENTURION_HOME") or os.path.expanduser("~/.centurion")
    return Path(base)


def inbox_dir() -> Path:
    """~/.centurion/fleet/messages — the same directory swarm already expects."""
    d = _home() / "fleet" / _INBOX_DIRNAME
    d.mkdir(parents=True, exist_ok=True)
    return d


def store_message(payload: dict[str, Any]) -> Path:
    """Write a received message to the inbox. Raises on failure.

    The caller must not report success unless this returns — a message that is
    acknowledged but not stored is worse than one that is refused, because the
    sender stops trying.

    Written to a temp file then renamed, so a crash mid-write cannot leave a
    half-file that later looks like a corrupt message.
    """
    message_id = str(payload.get("message_id") or "").strip()
    if not message_id:
        # Never silently invent an id — an unnamed message cannot be replied to
        # or deduplicated, and the sender believes it landed.
        raise ValueError("message_id is required")

    safe = "".join(c for c in message_id if c.isalnum() or c in "-_.")[:120]
    if not safe:
        raise ValueError("message_id has no usable characters")

    record = {
        "message_id": safe,
        "sender_id": str(payload.get("sender_id") or ""),
        "sender_name": str(payload.get("sender_name") or payload.get("sender_id") or "another Centurion"),
        "recipient_id": str(payload.get("recipient_id") or ""),
        "subject": str(payload.get("subject") or "(no subject)"),
        "body": str(payload.get("body") or "")[:_MAX_BODY_CHARS],
        "priority": str(payload.get("priority") or "normal"),
        "timestamp": payload.get("timestamp") or time.time(),
        "received_at": time.time(),
        "read": False,
    }

    target = inbox_dir() / f"{safe}.json"
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, target)
    return target


def list_messages(limit: int = 50, unread_only: bool = False) -> list[dict[str, Any]]:
    """Newest first. A malformed file is skipped, not fatal."""
    out: list[dict[str, Any]] = []
    try:
        files = sorted(inbox_dir().glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    except OSError:
        return out

    for path in files[: max(limit * 3, limit)]:
        try:
            rec = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(rec, dict):
            continue
        if unread_only and rec.get("read"):
            continue
        out.append(rec)
        if len(out) >= limit:
            break
    return out


def mark_read(message_id: str) -> bool:
    """Mark one message as read. Returns False if it is not there."""
    safe = "".join(c for c in str(message_id) if c.isalnum() or c in "-_.")[:120]
    if not safe:
        return False
    path = inbox_dir() / f"{safe}.json"
    try:
        rec = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    if not isinstance(rec, dict):
        return False
    rec["read"] = True
    path.write_text(json.dumps(rec, indent=2, ensure_ascii=False), encoding="utf-8")
    return True


def unread_count() -> int:
    return len(list_messages(limit=500, unread_only=True))
