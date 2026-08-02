"""Append-only license audit log under CENTURION_HOME/license/audit.jsonl."""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


def _license_dir() -> Path:
    from centurion_constants import get_centurion_home

    path = get_centurion_home() / "license"
    path.mkdir(parents=True, exist_ok=True)
    return path


def audit_path() -> Path:
    return _license_dir() / "audit.jsonl"


def append_audit(event: str, **fields: Any) -> None:
    """Append one JSON line. Never raises to callers."""
    record: Dict[str, Any] = {
        "ts": time.time(),
        "event": event,
    }
    for key, value in fields.items():
        if value is not None:
            record[key] = value
    path = audit_path()
    try:
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    except Exception as exc:
        logger.debug("license audit write failed: %s", exc)


def read_audit(limit: int = 200) -> List[Dict[str, Any]]:
    """Return the last *limit* audit records (oldest first among the slice)."""
    path = audit_path()
    if not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    records: List[Dict[str, Any]] = []
    for line in lines[-max(1, limit) :]:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            records.append(data)
    return records


def audit_for_support_bundle(limit: int = 100) -> Optional[List[Dict[str, Any]]]:
    """Snapshot for support bundles (no secrets expected)."""
    records = read_audit(limit=limit)
    return records or None
