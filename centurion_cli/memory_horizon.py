"""Memory Horizon snapshot for Sovereign Remote / Desktop Settings.

Aggregates Hot Cache (software char budgets), Session Recall (state.db vs
disk headroom), and Vault (opt-in sealed store vs disk) into one JSON payload.
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

DEFAULT_MEMORY_CHAR_LIMIT = 2200
DEFAULT_USER_CHAR_LIMIT = 1375


def _safe_file_chars(path: Path) -> int:
    try:
        if not path.is_file():
            return 0
        return len(path.read_text(encoding="utf-8").strip())
    except OSError:
        return 0


def _safe_file_bytes(path: Path) -> int:
    try:
        if not path.is_file():
            return 0
        return int(path.stat().st_size)
    except OSError:
        return 0


def _disk_free_bytes(path: Path) -> int:
    try:
        path.mkdir(parents=True, exist_ok=True)
        return int(shutil.disk_usage(path).free)
    except OSError:
        return 0


def _fill_ratio(used: int, free: int) -> float:
    """used / (used + free), clamped to [0, 1]."""
    used = max(0, int(used))
    free = max(0, int(free))
    total = used + free
    if total <= 0:
        return 0.0
    return min(1.0, max(0.0, used / total))


def _hot_cache_fill(used: int, limit: int) -> float:
    if limit <= 0:
        return 0.0
    return min(1.0, max(0.0, used / limit))


def build_memory_horizon_snapshot() -> dict[str, Any]:
    """Return a JSON-safe Memory Horizon snapshot for Settings gauges."""
    from centurion_constants import get_centurion_home

    home = get_centurion_home()
    free_bytes = _disk_free_bytes(home)

    memory_limit = DEFAULT_MEMORY_CHAR_LIMIT
    user_limit = DEFAULT_USER_CHAR_LIMIT
    try:
        from centurion_cli.config import load_config

        cfg = load_config()
        mem_cfg = cfg.get("memory") if isinstance(cfg, dict) else None
        if isinstance(mem_cfg, dict):
            memory_limit = int(mem_cfg.get("memory_char_limit", memory_limit) or memory_limit)
            user_limit = int(mem_cfg.get("user_char_limit", user_limit) or user_limit)
    except Exception:
        logger.debug("memory_horizon: using default hot-cache limits", exc_info=True)

    from tools.memory_tool import get_memory_dir

    mem_dir = get_memory_dir()
    memory_chars = _safe_file_chars(mem_dir / "MEMORY.md")
    user_chars = _safe_file_chars(mem_dir / "USER.md")
    used_chars = memory_chars + user_chars
    limit_chars = memory_limit + user_limit

    hot_cache = {
        "memory_chars": memory_chars,
        "memory_limit": memory_limit,
        "user_chars": user_chars,
        "user_limit": user_limit,
        "used_chars": used_chars,
        "limit_chars": limit_chars,
        "fill_ratio": round(_hot_cache_fill(used_chars, limit_chars), 4),
    }

    sessions = 0
    messages = 0
    db_bytes = 0
    try:
        from centurion_state import DEFAULT_DB_PATH, SessionDB

        db_path = Path(DEFAULT_DB_PATH)
        db_bytes = _safe_file_bytes(db_path)
        db = SessionDB()
        try:
            sessions = int(db.session_count())
            messages = int(db.message_count())
        finally:
            try:
                db.close()
            except Exception:
                pass
    except Exception:
        logger.debug("memory_horizon: session recall unavailable", exc_info=True)

    session_recall = {
        "sessions": sessions,
        "messages": messages,
        "db_bytes": db_bytes,
        "free_bytes": free_bytes,
        "fill_ratio": round(_fill_ratio(db_bytes, free_bytes), 4),
    }

    vault_enabled = False
    try:
        from centurion_cli.config import load_config

        cfg = load_config()
        vault_cfg = cfg.get("vault") if isinstance(cfg, dict) else None
        if isinstance(vault_cfg, dict):
            vault_enabled = bool(vault_cfg.get("enabled", False))
    except Exception:
        pass

    initialized = False
    unlocked = False
    total_entries = 0
    counts = {"core": 0, "experiential": 0, "pattern": 0}
    pending = 0
    vault_db_bytes = 0
    try:
        from agent.vault import is_initialized, open_vault
        from agent.vault.paths import db_path as vault_db_path

        initialized = bool(is_initialized())
        vault_db_bytes = _safe_file_bytes(Path(vault_db_path()))
        if initialized:
            vault = open_vault(writes_allowed=False)
            st = vault.status()
            unlocked = bool(st.get("unlocked"))
            total_entries = int(st.get("total_entries") or 0)
            pending = int(st.get("pending_proposals") or 0)
            raw_counts = st.get("counts") or {}
            if isinstance(raw_counts, dict):
                counts = {
                    "core": int(raw_counts.get("core") or 0),
                    "experiential": int(raw_counts.get("experiential") or 0),
                    "pattern": int(raw_counts.get("pattern") or 0),
                }
    except Exception:
        logger.debug("memory_horizon: vault status unavailable", exc_info=True)

    # Off / uninitialized → empty gauge. Locked/unlocked → disk headroom formula.
    if not initialized or not vault_enabled:
        vault_fill = 0.0
    else:
        vault_fill = _fill_ratio(vault_db_bytes, free_bytes)

    vault = {
        "enabled": vault_enabled,
        "initialized": initialized,
        "unlocked": unlocked,
        "total_entries": total_entries,
        "pending_proposals": pending,
        "counts": counts,
        "db_bytes": vault_db_bytes,
        "free_bytes": free_bytes,
        "fill_ratio": round(vault_fill, 4),
    }

    return {
        "hot_cache": hot_cache,
        "session_recall": session_recall,
        "vault": vault,
    }
