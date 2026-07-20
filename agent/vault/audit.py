"""Append-only audit hash chain for Vault events."""

from __future__ import annotations

import hashlib
import sqlite3
from datetime import datetime, timezone
from typing import Any, Optional


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _hash_payload(payload: dict[str, Any]) -> str:
    # Stable, secret-free fingerprint
    items = sorted((str(k), str(v)) for k, v in payload.items())
    blob = "|".join(f"{k}={v}" for k, v in items).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def append_audit(
    conn: sqlite3.Connection,
    event_type: str,
    payload: Optional[dict[str, Any]] = None,
) -> str:
    """Append an audit event; returns entry_hash."""
    payload = payload or {}
    payload_hash = _hash_payload(payload)
    prev = conn.execute(
        "SELECT entry_hash FROM audit_events ORDER BY seq DESC LIMIT 1"
    ).fetchone()
    prev_hash = prev[0] if prev else ("0" * 64)
    ts = _utc_now()
    material = f"{ts}|{event_type}|{payload_hash}|{prev_hash}".encode("utf-8")
    entry_hash = hashlib.sha256(material).hexdigest()
    conn.execute(
        "INSERT INTO audit_events(ts, event_type, payload_hash, prev_hash, entry_hash) "
        "VALUES (?, ?, ?, ?, ?)",
        (ts, event_type, payload_hash, prev_hash, entry_hash),
    )
    return entry_hash
