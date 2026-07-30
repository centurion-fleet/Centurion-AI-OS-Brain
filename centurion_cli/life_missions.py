"""Offline Life Missions store — Subjects → Missions → Targets on the Brain.

Canonical path: ``{get_centurion_home()}/life/life.db``.
Projects LIFE_MISSION.md via ``mission_sync`` so the agent prompt stays stable.
No portal / Supabase — Remote and GTK talk to this module only.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from centurion_constants import get_centurion_home

_SCHEMA_VERSION = 4

MISSION_PHASES = frozenset(
    {"briefing", "discovery", "planning", "executing", "verifying", "done"}
)
MISSION_TYPES = frozenset({"primary", "supporting", "dream"})
IMPACT_RATINGS = frozenset({"high", "medium", "low"})
TARGET_TYPES = frozenset({"essential", "shouldHave", "niceToHave"})
TARGET_STATUSES = frozenset({"not_started", "in_progress", "complete", "blocked"})
DOC_TYPES = frozenset(
    {"research", "analysis", "content", "report", "plan", "other"}
)
DOC_SOURCES = frozenset({"agent", "user", "import"})
THOUGHT_TYPES = frozenset(
    {
        "thought",
        "tool_start",
        "tool_result",
        "target_update",
        "artifact",
        "decision",
        "handoff",
    }
)


def life_dir() -> Path:
    path = get_centurion_home() / "life"
    path.mkdir(parents=True, exist_ok=True)
    return path


def life_db_path() -> Path:
    return life_dir() / "life.db"


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _new_id() -> str:
    return str(uuid.uuid4())


@contextmanager
def _conn() -> Iterator[sqlite3.Connection]:
    path = life_db_path()
    conn = sqlite3.connect(str(path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    try:
        ensure_schema(conn)
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


_SCHEMA_READY = False
_SCHEMA_READY_PATH: str | None = None
_SCHEMA_READY_LOCK = threading.Lock()
_REHOME_ATTEMPTED = False
_REHOME_ATTEMPTED_PATH: str | None = None
_REHOME_IN_PROGRESS = False


def _run_rehome_once() -> None:
    """Process-once wrapper; skipped while rehome itself is running."""
    global _REHOME_ATTEMPTED, _REHOME_ATTEMPTED_PATH, _REHOME_IN_PROGRESS
    if _REHOME_IN_PROGRESS:
        return
    path = str(life_db_path())
    if _REHOME_ATTEMPTED and _REHOME_ATTEMPTED_PATH == path:
        return
    _REHOME_ATTEMPTED = True
    _REHOME_ATTEMPTED_PATH = path
    _REHOME_IN_PROGRESS = True
    try:
        rehome_primary_import_orphans()
    except Exception:
        pass
    finally:
        _REHOME_IN_PROGRESS = False


def ensure_schema_once() -> None:
    """Warm-path: ensure schema + one-shot markdown bootstrap per process+db path."""
    global _SCHEMA_READY, _SCHEMA_READY_PATH
    path = str(life_db_path())
    if _SCHEMA_READY and _SCHEMA_READY_PATH == path:
        return
    with _SCHEMA_READY_LOCK:
        if _SCHEMA_READY and _SCHEMA_READY_PATH == path:
            return
        ensure_schema()
        _run_rehome_once()
        try:
            # Daemon warm only — never call from hot read paths (get_stack / lists).
            bootstrap_from_markdown_if_empty()
        except Exception:
            pass
        _SCHEMA_READY = True
        _SCHEMA_READY_PATH = path


def ensure_schema(conn: sqlite3.Connection | None = None) -> None:
    global _SCHEMA_READY, _SCHEMA_READY_PATH
    path = str(life_db_path())
    # Hot path: schema already ensured for this DB path — skip executescript.
    if _SCHEMA_READY and _SCHEMA_READY_PATH == path and conn is not None:
        return
    own = conn is None
    if own:
        conn = sqlite3.connect(path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
    assert conn is not None
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS life_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_subjects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          icon TEXT NOT NULL DEFAULT 'list.bullet',
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_missions (
          id TEXT PRIMARY KEY,
          subject_id TEXT REFERENCES life_subjects(id) ON DELETE SET NULL,
          title TEXT NOT NULL DEFAULT '',
          statement TEXT NOT NULL DEFAULT '',
          situation TEXT NOT NULL DEFAULT '',
          why TEXT NOT NULL DEFAULT '',
          purpose TEXT NOT NULL DEFAULT '',
          phase TEXT NOT NULL DEFAULT 'executing',
          mission_type TEXT NOT NULL DEFAULT 'supporting',
          impact_rating TEXT NOT NULL DEFAULT 'medium',
          stack_sort_order INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'active',
          profile_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_mission_stack (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          primary_mission_id TEXT REFERENCES life_missions(id) ON DELETE SET NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_dreams (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          sort_order INTEGER NOT NULL DEFAULT 0,
          promoted_to_mission_id TEXT REFERENCES life_missions(id) ON DELETE SET NULL,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_targets (
          id TEXT PRIMARY KEY,
          mission_id TEXT NOT NULL REFERENCES life_missions(id) ON DELETE CASCADE,
          sequence_number INTEGER NOT NULL,
          title TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          target_type TEXT NOT NULL DEFAULT 'essential',
          status TEXT NOT NULL DEFAULT 'not_started',
          focus_target INTEGER NOT NULL DEFAULT 0,
          sequence_warning TEXT,
          started_at TEXT,
          completed_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          UNIQUE (mission_id, sequence_number)
        );

        CREATE TABLE IF NOT EXISTS life_decisions (
          id TEXT PRIMARY KEY,
          mission_id TEXT REFERENCES life_missions(id) ON DELETE SET NULL,
          target_id TEXT REFERENCES life_targets(id) ON DELETE SET NULL,
          title TEXT NOT NULL,
          context TEXT NOT NULL DEFAULT '',
          options_json TEXT NOT NULL DEFAULT '[]',
          chosen TEXT NOT NULL DEFAULT '',
          human_said TEXT NOT NULL DEFAULT '',
          ai_recommendation TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_thoughts (
          id TEXT PRIMARY KEY,
          mission_id TEXT REFERENCES life_missions(id) ON DELETE SET NULL,
          target_id TEXT REFERENCES life_targets(id) ON DELETE SET NULL,
          activity_type TEXT NOT NULL DEFAULT 'thought',
          summary TEXT NOT NULL,
          detail TEXT NOT NULL DEFAULT '',
          progress REAL,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_mission_state (
          mission_id TEXT PRIMARY KEY REFERENCES life_missions(id) ON DELETE CASCADE,
          focus_target_id TEXT REFERENCES life_targets(id) ON DELETE SET NULL,
          completed_target_ids_json TEXT NOT NULL DEFAULT '[]',
          last_activity_at TEXT,
          last_decision_id TEXT REFERENCES life_decisions(id) ON DELETE SET NULL,
          checkpoint_json TEXT NOT NULL DEFAULT '{}',
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS life_documents (
          id TEXT PRIMARY KEY,
          mission_id TEXT NOT NULL REFERENCES life_missions(id) ON DELETE CASCADE,
          target_id TEXT REFERENCES life_targets(id) ON DELETE SET NULL,
          title TEXT NOT NULL,
          doc_type TEXT NOT NULL DEFAULT 'other',
          summary TEXT NOT NULL DEFAULT '',
          body_md TEXT NOT NULL DEFAULT '',
          plan_id TEXT,
          source TEXT NOT NULL DEFAULT 'agent',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        """
    )
    # Only write schema_version when it actually differs (reads must stay read-only).
    row = conn.execute(
        "SELECT value FROM life_meta WHERE key = 'schema_version'"
    ).fetchone()
    current = str(row["value"]) if row is not None else ""
    try:
        prev_ver = int(current) if current else 0
    except ValueError:
        prev_ver = 0

    # v3: FTS5 index over life_documents (create before bumping schema_version).
    if prev_ver < 3:
        _migrate_documents_fts(conn)

    # v4: Primary import rehome runs after schema ready (see ensure_schema_once).
    # Marker only — actual move is rehome_primary_import_orphans().

    conn.execute(
        "INSERT OR IGNORE INTO life_meta(key, value) VALUES ('data_version', '0')"
    )

    if current != str(_SCHEMA_VERSION):
        conn.execute(
            "INSERT OR IGNORE INTO life_meta(key, value) VALUES ('schema_version', ?)",
            (str(_SCHEMA_VERSION),),
        )
        conn.execute(
            "UPDATE life_meta SET value = ? WHERE key = 'schema_version'",
            (str(_SCHEMA_VERSION),),
        )
    now = _utc_now()
    conn.execute(
        "INSERT OR IGNORE INTO life_mission_stack(id, primary_mission_id, updated_at) VALUES (1, NULL, ?)",
        (now,),
    )
    row = conn.execute(
        "SELECT id FROM life_subjects WHERE name = ? LIMIT 1",
        ("Uncategorised",),
    ).fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO life_subjects(id, name, icon, sort_order, created_at, updated_at) "
            "VALUES (?, ?, ?, 0, ?, ?)",
            (_new_id(), "Uncategorised", "folder", now, now),
        )
    _SCHEMA_READY = True
    _SCHEMA_READY_PATH = path
    if own:
        conn.commit()
        conn.close()
        _run_rehome_once()
    else:
        # Schema ready on this connection; commit so rehome's nested opens see it.
        conn.commit()
        _run_rehome_once()


def _migrate_documents_fts(conn: sqlite3.Connection) -> None:
    """Create life_documents_fts + sync triggers and backfill existing rows."""
    conn.executescript(
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS life_documents_fts USING fts5(
          doc_id UNINDEXED,
          title,
          summary,
          body_md,
          tokenize='porter unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS life_documents_fts_ai
        AFTER INSERT ON life_documents BEGIN
          INSERT INTO life_documents_fts(doc_id, title, summary, body_md)
          VALUES (new.id, new.title, new.summary, new.body_md);
        END;

        CREATE TRIGGER IF NOT EXISTS life_documents_fts_ad
        AFTER DELETE ON life_documents BEGIN
          DELETE FROM life_documents_fts WHERE doc_id = old.id;
        END;

        CREATE TRIGGER IF NOT EXISTS life_documents_fts_au
        AFTER UPDATE ON life_documents BEGIN
          DELETE FROM life_documents_fts WHERE doc_id = old.id;
          INSERT INTO life_documents_fts(doc_id, title, summary, body_md)
          VALUES (new.id, new.title, new.summary, new.body_md);
        END;
        """
    )
    fts_count = conn.execute("SELECT COUNT(*) AS n FROM life_documents_fts").fetchone()[
        "n"
    ]
    if int(fts_count or 0) == 0:
        conn.execute(
            "INSERT INTO life_documents_fts(doc_id, title, summary, body_md) "
            "SELECT id, title, summary, body_md FROM life_documents"
        )


def get_data_version() -> int:
    """Monotonic revision counter for life store changes (thoughts/documents)."""
    with _conn() as conn:
        row = conn.execute(
            "SELECT value FROM life_meta WHERE key = 'data_version'"
        ).fetchone()
        if row is None:
            return 0
        try:
            return int(row["value"])
        except (TypeError, ValueError):
            return 0


def bump_data_version(conn: sqlite3.Connection) -> int:
    """Increment ``data_version`` on an open connection; return the new value."""
    conn.execute(
        "INSERT OR IGNORE INTO life_meta(key, value) VALUES ('data_version', '0')"
    )
    conn.execute(
        "UPDATE life_meta SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) "
        "WHERE key = 'data_version'"
    )
    row = conn.execute(
        "SELECT value FROM life_meta WHERE key = 'data_version'"
    ).fetchone()
    try:
        return int(row["value"]) if row is not None else 0
    except (TypeError, ValueError):
        return 0


def _sanitize_fts_query(query: str) -> str:
    """Strip FTS5 special characters; return space-joined terms or empty."""
    cleaned = re.sub(r'["*\(\)]', " ", str(query or ""))
    cleaned = re.sub(r"[^\w\s\-']", " ", cleaned, flags=re.UNICODE)
    terms = [t for t in cleaned.split() if t]
    return " ".join(terms)


def bootstrap_from_markdown_if_empty() -> dict[str, Any]:
    """Import LIFE_MISSION.md into life.db when no missions exist yet."""
    with _conn() as conn:
        count = conn.execute("SELECT COUNT(*) AS n FROM life_missions").fetchone()["n"]
        if count > 0:
            return {"imported": False, "missions": count}
        try:
            from centurion_cli.mission_sync import read_mission
        except Exception:
            return {"imported": False, "missions": 0}
        mission = read_mission()
        statement = str(mission.get("statement") or "").strip()
        targets = mission.get("targets") if isinstance(mission.get("targets"), list) else []
        if not statement and not targets and not mission.get("exists"):
            return {"imported": False, "missions": 0}
        subject = conn.execute(
            "SELECT id FROM life_subjects WHERE name = ? LIMIT 1",
            ("Uncategorised",),
        ).fetchone()
        subject_id = subject["id"] if subject else None
        now = _utc_now()
        mid = str(mission.get("id") or mission.get("mission_id") or _new_id())
        profile = mission.get("profile") if isinstance(mission.get("profile"), dict) else {}
        why = str(profile.get("whyThisMission") or "").strip()
        conn.execute(
            "INSERT INTO life_missions("
            "id, subject_id, title, statement, situation, why, purpose, phase, "
            "mission_type, impact_rating, stack_sort_order, status, profile_json, "
            "created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                mid,
                subject_id,
                statement[:80] or "Life Mission",
                statement,
                "",
                why,
                "",
                "executing",
                "primary",
                "high",
                0,
                "active",
                json.dumps(profile),
                now,
                now,
            ),
        )
        conn.execute(
            "UPDATE life_mission_stack SET primary_mission_id = ?, updated_at = ? WHERE id = 1",
            (mid, now),
        )
        for i, item in enumerate(targets):
            if not isinstance(item, dict):
                continue
            title = str(item.get("title") or "").strip()
            if not title:
                continue
            tid = str(item.get("id") or _new_id())
            conn.execute(
                "INSERT INTO life_targets("
                "id, mission_id, sequence_number, title, description, target_type, "
                "status, focus_target, created_at, updated_at) "
                "VALUES (?,?,?,?,?,?,?,0,?,?)",
                (
                    tid,
                    mid,
                    i + 1,
                    title,
                    str(item.get("description") or ""),
                    "essential",
                    "not_started",
                    now,
                    now,
                ),
            )
        _sync_focus(conn, mid)
        _export_primary_markdown(conn)
        return {"imported": True, "mission_id": mid, "missions": 1}


def _row_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {k: row[k] for k in row.keys()}


def _export_primary_markdown(conn: sqlite3.Connection) -> None:
    stack = conn.execute(
        "SELECT primary_mission_id FROM life_mission_stack WHERE id = 1"
    ).fetchone()
    mid = stack["primary_mission_id"] if stack else None
    if not mid:
        row = conn.execute(
            "SELECT id FROM life_missions WHERE mission_type = 'primary' LIMIT 1"
        ).fetchone()
        mid = row["id"] if row else None
    if not mid:
        row = conn.execute(
            "SELECT id FROM life_missions ORDER BY stack_sort_order, created_at LIMIT 1"
        ).fetchone()
        mid = row["id"] if row else None
    if not mid:
        return
    mission = conn.execute("SELECT * FROM life_missions WHERE id = ?", (mid,)).fetchone()
    if not mission:
        return
    targets = conn.execute(
        "SELECT * FROM life_targets WHERE mission_id = ? ORDER BY sequence_number",
        (mid,),
    ).fetchall()
    try:
        profile = json.loads(mission["profile_json"] or "{}")
    except json.JSONDecodeError:
        profile = {}
    if mission["why"] and not profile.get("whyThisMission"):
        profile["whyThisMission"] = mission["why"]
    fields = {
        "id": mission["id"],
        "statement": mission["statement"] or mission["title"],
        "targets": [
            {
                "id": t["id"],
                "title": t["title"],
                "description": t["description"],
            }
            for t in targets
        ],
        "profile": profile,
    }
    try:
        from centurion_cli.mission_sync import write_mission

        write_mission(fields)
    except Exception:
        pass


def _sync_focus(conn: sqlite3.Connection, mission_id: str) -> str | None:
    """Set focus_target to first incomplete essential, else first incomplete."""
    targets = conn.execute(
        "SELECT * FROM life_targets WHERE mission_id = ? ORDER BY sequence_number",
        (mission_id,),
    ).fetchall()
    conn.execute(
        "UPDATE life_targets SET focus_target = 0 WHERE mission_id = ?",
        (mission_id,),
    )
    incomplete = [t for t in targets if t["status"] != "complete"]
    essential = [t for t in incomplete if t["target_type"] == "essential"]
    pick = essential or incomplete
    focus_id = pick[0]["id"] if pick else None
    if focus_id:
        conn.execute(
            "UPDATE life_targets SET focus_target = 1 WHERE id = ?",
            (focus_id,),
        )
    completed_ids = [t["id"] for t in targets if t["status"] == "complete"]
    now = _utc_now()
    conn.execute(
        "INSERT INTO life_mission_state("
        "mission_id, focus_target_id, completed_target_ids_json, last_activity_at, "
        "checkpoint_json, updated_at) VALUES (?,?,?,?, '{}', ?) "
        "ON CONFLICT(mission_id) DO UPDATE SET "
        "focus_target_id=excluded.focus_target_id, "
        "completed_target_ids_json=excluded.completed_target_ids_json, "
        "last_activity_at=excluded.last_activity_at, "
        "updated_at=excluded.updated_at",
        (mission_id, focus_id, json.dumps(completed_ids), now, now),
    )
    return focus_id


def _validate_sequence(conn: sqlite3.Connection, mission_id: str) -> list[dict[str, str]]:
    targets = conn.execute(
        "SELECT * FROM life_targets WHERE mission_id = ? ORDER BY sequence_number",
        (mission_id,),
    ).fetchall()
    warnings: list[dict[str, str]] = []
    for i in range(len(targets) - 1):
        cur, nxt = targets[i], targets[i + 1]
        if nxt["sequence_number"] == cur["sequence_number"]:
            warnings.append(
                {
                    "type": "duplicate_sequence",
                    "message": f"Duplicate sequence #{cur['sequence_number']}",
                }
            )
        if nxt["sequence_number"] - cur["sequence_number"] > 1:
            warnings.append(
                {
                    "type": "gap",
                    "message": (
                        f"Gap between #{cur['sequence_number']} and #{nxt['sequence_number']}"
                    ),
                }
            )
    completed = [t for t in targets if t["status"] == "complete"]
    incomplete = [t for t in targets if t["status"] != "complete"]
    for done in completed:
        for pending in incomplete:
            if pending["sequence_number"] < done["sequence_number"]:
                warnings.append(
                    {
                        "type": "wrong_order",
                        "message": (
                            f"Target #{done['sequence_number']} completed before "
                            f"#{pending['sequence_number']}"
                        ),
                    }
                )
    text = "; ".join(w["message"] for w in warnings) if warnings else None
    conn.execute(
        "UPDATE life_targets SET sequence_warning = ? WHERE mission_id = ?",
        (text, mission_id),
    )
    return warnings


# ─── Subjects ────────────────────────────────────────────────────────────────


def list_subjects() -> list[dict[str, Any]]:
    with _conn() as conn:
        rows = conn.execute(
            "SELECT * FROM life_subjects ORDER BY sort_order, name"
        ).fetchall()
        return [_row_dict(r) for r in rows]  # type: ignore[misc]


def put_subject(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    sid = str(fields.get("id") or _new_id())
    name = str(fields.get("name") or "").strip()
    if not name:
        raise ValueError("name required")
    icon = str(fields.get("icon") or fields.get("emoji") or "list.bullet")
    sort_order = int(fields.get("sort_order") or 0)
    with _conn() as conn:
        existing = conn.execute(
            "SELECT id FROM life_subjects WHERE id = ?", (sid,)
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE life_subjects SET name=?, icon=?, sort_order=?, updated_at=? WHERE id=?",
                (name, icon, sort_order, now, sid),
            )
        else:
            conn.execute(
                "INSERT INTO life_subjects(id, name, icon, sort_order, created_at, updated_at) "
                "VALUES (?,?,?,?,?,?)",
                (sid, name, icon, sort_order, now, now),
            )
        row = conn.execute("SELECT * FROM life_subjects WHERE id = ?", (sid,)).fetchone()
        return _row_dict(row)  # type: ignore[return-value]


def delete_subject(subject_id: str) -> bool:
    with _conn() as conn:
        uncat = conn.execute(
            "SELECT id FROM life_subjects WHERE name = ? LIMIT 1",
            ("Uncategorised",),
        ).fetchone()
        if uncat and uncat["id"] != subject_id:
            conn.execute(
                "UPDATE life_missions SET subject_id = ? WHERE subject_id = ?",
                (uncat["id"], subject_id),
            )
        conn.execute("DELETE FROM life_subjects WHERE id = ?", (subject_id,))
        return True


def reorder_subjects(ordered_ids: list[str]) -> None:
    with _conn() as conn:
        now = _utc_now()
        for i, sid in enumerate(ordered_ids):
            conn.execute(
                "UPDATE life_subjects SET sort_order = ?, updated_at = ? WHERE id = ?",
                (i, now, sid),
            )


# ─── Dreams ──────────────────────────────────────────────────────────────────


def list_dreams(*, include_promoted: bool = False) -> list[dict[str, Any]]:
    with _conn() as conn:
        if include_promoted:
            rows = conn.execute(
                "SELECT * FROM life_dreams ORDER BY sort_order, created_at"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM life_dreams WHERE promoted_to_mission_id IS NULL "
                "ORDER BY sort_order, created_at"
            ).fetchall()
        return [_row_dict(r) for r in rows]  # type: ignore[misc]


def put_dream(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    did = str(fields.get("id") or _new_id())
    title = str(fields.get("title") or "").strip()
    if not title:
        raise ValueError("title required")
    description = str(fields.get("description") or "")
    with _conn() as conn:
        existing = conn.execute(
            "SELECT id, sort_order FROM life_dreams WHERE id = ?", (did,)
        ).fetchone()
        if existing:
            sort_order = int(fields.get("sort_order", existing["sort_order"]))
            conn.execute(
                "UPDATE life_dreams SET title=?, description=?, sort_order=? WHERE id=?",
                (title, description, sort_order, did),
            )
        else:
            max_row = conn.execute(
                "SELECT COALESCE(MAX(sort_order), -1) AS m FROM life_dreams"
            ).fetchone()
            sort_order = int(fields.get("sort_order", max_row["m"] + 1))
            conn.execute(
                "INSERT INTO life_dreams(id, title, description, sort_order, created_at) "
                "VALUES (?,?,?,?,?)",
                (did, title, description, sort_order, now),
            )
        row = conn.execute("SELECT * FROM life_dreams WHERE id = ?", (did,)).fetchone()
        return _row_dict(row)  # type: ignore[return-value]


def delete_dream(dream_id: str) -> bool:
    with _conn() as conn:
        conn.execute("DELETE FROM life_dreams WHERE id = ?", (dream_id,))
        return True


# ─── Missions ────────────────────────────────────────────────────────────────


def _mission_dict(conn: sqlite3.Connection, row: sqlite3.Row) -> dict[str, Any]:
    d = _row_dict(row)
    assert d is not None
    try:
        d["profile"] = json.loads(d.pop("profile_json") or "{}")
    except json.JSONDecodeError:
        d["profile"] = {}
        d.pop("profile_json", None)
    targets = conn.execute(
        "SELECT * FROM life_targets WHERE mission_id = ? ORDER BY sequence_number",
        (d["id"],),
    ).fetchall()
    d["targets"] = [_row_dict(t) for t in targets]
    d["completed_target_count"] = sum(1 for t in targets if t["status"] == "complete")
    d["target_count"] = len(targets)
    state = conn.execute(
        "SELECT * FROM life_mission_state WHERE mission_id = ?",
        (d["id"],),
    ).fetchone()
    if state:
        sd = _row_dict(state)
        assert sd is not None
        try:
            sd["completed_target_ids"] = json.loads(
                sd.pop("completed_target_ids_json") or "[]"
            )
        except json.JSONDecodeError:
            sd["completed_target_ids"] = []
        try:
            sd["checkpoint"] = json.loads(sd.pop("checkpoint_json") or "{}")
        except json.JSONDecodeError:
            sd["checkpoint"] = {}
        d["state"] = sd
    else:
        d["state"] = None
    return d


def list_missions() -> list[dict[str, Any]]:
    with _conn() as conn:
        rows = conn.execute(
            "SELECT * FROM life_missions ORDER BY stack_sort_order, created_at"
        ).fetchall()
        return [_mission_dict(conn, r) for r in rows]


def get_mission(mission_id: str) -> dict[str, Any] | None:
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM life_missions WHERE id = ?", (mission_id,)
        ).fetchone()
        if not row:
            return None
        return _mission_dict(conn, row)


def put_mission(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    mid = str(fields.get("id") or _new_id())
    title = str(fields.get("title") or fields.get("statement") or "Mission").strip()
    statement = str(fields.get("statement") or title).strip()
    phase = str(fields.get("phase") or "executing")
    if phase not in MISSION_PHASES:
        phase = "executing"
    mission_type = str(fields.get("mission_type") or "supporting")
    if mission_type not in MISSION_TYPES:
        mission_type = "supporting"
    impact = str(fields.get("impact_rating") or "medium")
    if impact not in IMPACT_RATINGS:
        impact = "medium"
    profile = fields.get("profile") if isinstance(fields.get("profile"), dict) else {}
    with _conn() as conn:
        existing = conn.execute(
            "SELECT id FROM life_missions WHERE id = ?", (mid,)
        ).fetchone()
        subject_id = fields.get("subject_id")
        situation = str(fields.get("situation") or "")
        why = str(fields.get("why") or profile.get("whyThisMission") or "")
        purpose = str(fields.get("purpose") or "")
        stack_sort = int(fields.get("stack_sort_order") or 0)
        status = str(fields.get("status") or "active")
        profile_json = json.dumps(profile)
        if existing:
            conn.execute(
                "UPDATE life_missions SET subject_id=?, title=?, statement=?, situation=?, "
                "why=?, purpose=?, phase=?, mission_type=?, impact_rating=?, "
                "stack_sort_order=?, status=?, profile_json=?, updated_at=? WHERE id=?",
                (
                    subject_id,
                    title,
                    statement,
                    situation,
                    why,
                    purpose,
                    phase,
                    mission_type,
                    impact,
                    stack_sort,
                    status,
                    profile_json,
                    now,
                    mid,
                ),
            )
        else:
            conn.execute(
                "INSERT INTO life_missions("
                "id, subject_id, title, statement, situation, why, purpose, phase, "
                "mission_type, impact_rating, stack_sort_order, status, profile_json, "
                "created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    mid,
                    subject_id,
                    title,
                    statement,
                    situation,
                    why,
                    purpose,
                    phase,
                    mission_type,
                    impact,
                    stack_sort,
                    status,
                    profile_json,
                    now,
                    now,
                ),
            )
        if isinstance(fields.get("targets"), list):
            conn.execute("DELETE FROM life_targets WHERE mission_id = ?", (mid,))
            for i, item in enumerate(fields["targets"]):
                if not isinstance(item, dict):
                    continue
                ttitle = str(item.get("title") or "").strip()
                if not ttitle:
                    continue
                tid = str(item.get("id") or _new_id())
                ttype = str(item.get("target_type") or "essential")
                if ttype not in TARGET_TYPES:
                    ttype = "essential"
                tstatus = str(item.get("status") or "not_started")
                if tstatus not in TARGET_STATUSES:
                    tstatus = "not_started"
                conn.execute(
                    "INSERT INTO life_targets("
                    "id, mission_id, sequence_number, title, description, target_type, "
                    "status, focus_target, started_at, completed_at, created_at, updated_at) "
                    "VALUES (?,?,?,?,?,?,?,0,?,?,?,?)",
                    (
                        tid,
                        mid,
                        int(item.get("sequence_number") or i + 1),
                        ttitle,
                        str(item.get("description") or ""),
                        ttype,
                        tstatus,
                        item.get("started_at"),
                        item.get("completed_at"),
                        now,
                        now,
                    ),
                )
        _sync_focus(conn, mid)
        _validate_sequence(conn, mid)
        if mission_type == "primary":
            conn.execute(
                "UPDATE life_missions SET mission_type = 'supporting' "
                "WHERE mission_type = 'primary' AND id != ?",
                (mid,),
            )
            conn.execute(
                "UPDATE life_mission_stack SET primary_mission_id = ?, updated_at = ? WHERE id = 1",
                (mid, now),
            )
        _export_primary_markdown(conn)
        row = conn.execute("SELECT * FROM life_missions WHERE id = ?", (mid,)).fetchone()
        return _mission_dict(conn, row)


# ─── Stack ───────────────────────────────────────────────────────────────────


def get_stack() -> dict[str, Any]:
    with _conn() as conn:
        stack = conn.execute("SELECT * FROM life_mission_stack WHERE id = 1").fetchone()
        missions = [
            _mission_dict(conn, r)
            for r in conn.execute(
                "SELECT * FROM life_missions ORDER BY stack_sort_order, created_at"
            ).fetchall()
        ]
        primary_id = stack["primary_mission_id"] if stack else None
        primary = next((m for m in missions if m["id"] == primary_id), None)
        if primary is None:
            primary = next((m for m in missions if m.get("mission_type") == "primary"), None)
        supporting = [
            m
            for m in missions
            if m["id"] != (primary or {}).get("id")
            and m.get("mission_type") != "dream"
            and not (
                isinstance(m.get("profile"), dict)
                and m["profile"].get("hidden_from_stack")
            )
        ]
        dreams = [
            _row_dict(r)
            for r in conn.execute(
                "SELECT * FROM life_dreams WHERE promoted_to_mission_id IS NULL "
                "ORDER BY sort_order"
            ).fetchall()
        ]
        return {
            "primary": primary,
            "supporting": supporting,
            "dreams": dreams,
            "primary_mission_id": (primary or {}).get("id"),
        }


def deck_snapshot(
    *,
    thought_limit: int = 32,
    document_limit: int = 5,
) -> dict[str, Any]:
    """One round-trip hydration for Focus: stack + thoughts + primary doc teasers.

    Document teasers omit ``body_md`` so the payload stays small for frame-1 paint.
    """
    stack = get_stack()
    thoughts = list_thoughts(limit=max(1, min(int(thought_limit or 32), 80)))
    primary = stack.get("primary") if isinstance(stack, dict) else None
    primary_id = (
        str((primary or {}).get("id") or "").strip() if isinstance(primary, dict) else ""
    )
    documents: list[dict[str, Any]] = []
    if primary_id:
        for doc in list_documents(mission_id=primary_id, limit=max(1, min(int(document_limit or 5), 20))):
            documents.append(
                {
                    "id": doc.get("id"),
                    "mission_id": doc.get("mission_id"),
                    "title": doc.get("title"),
                    "doc_type": doc.get("doc_type"),
                    "summary": doc.get("summary"),
                    "source": doc.get("source"),
                    "updated_at": doc.get("updated_at"),
                    "created_at": doc.get("created_at"),
                }
            )
    return {
        "stack": stack,
        "thoughts": thoughts,
        "primary_documents": documents,
        "primary_document_count": len(documents),
        "data_version": get_data_version(),
    }


def set_primary(mission_id: str | None) -> dict[str, Any]:
    now = _utc_now()
    with _conn() as conn:
        if mission_id:
            conn.execute(
                "UPDATE life_missions SET mission_type = 'supporting' WHERE mission_type = 'primary'"
            )
            conn.execute(
                "UPDATE life_missions SET mission_type = 'primary', updated_at = ? WHERE id = ?",
                (now, mission_id),
            )
        conn.execute(
            "UPDATE life_mission_stack SET primary_mission_id = ?, updated_at = ? WHERE id = 1",
            (mission_id, now),
        )
        _export_primary_markdown(conn)
    return get_stack()


def reorder_supporting(ordered_ids: list[str]) -> dict[str, Any]:
    now = _utc_now()
    with _conn() as conn:
        for i, mid in enumerate(ordered_ids):
            conn.execute(
                "UPDATE life_missions SET stack_sort_order = ?, updated_at = ? WHERE id = ?",
                (i, now, mid),
            )
    return get_stack()


def promote_dream(dream_id: str, *, subject_id: str | None = None) -> dict[str, Any]:
    now = _utc_now()
    with _conn() as conn:
        dream = conn.execute(
            "SELECT * FROM life_dreams WHERE id = ?", (dream_id,)
        ).fetchone()
        if not dream:
            raise ValueError("Dream not found")
        if dream["promoted_to_mission_id"]:
            raise ValueError("Dream already promoted")
        mid = _new_id()
        if not subject_id:
            uncat = conn.execute(
                "SELECT id FROM life_subjects WHERE name = ? LIMIT 1",
                ("Uncategorised",),
            ).fetchone()
            subject_id = uncat["id"] if uncat else None
        conn.execute(
            "INSERT INTO life_missions("
            "id, subject_id, title, statement, situation, why, purpose, phase, "
            "mission_type, impact_rating, stack_sort_order, status, profile_json, "
            "created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                mid,
                subject_id,
                dream["title"],
                dream["title"],
                "",
                "",
                dream["description"] or "",
                "briefing",
                "supporting",
                "medium",
                0,
                "active",
                "{}",
                now,
                now,
            ),
        )
        conn.execute(
            "UPDATE life_dreams SET promoted_to_mission_id = ? WHERE id = ?",
            (mid, dream_id),
        )
        _sync_focus(conn, mid)
        _export_primary_markdown(conn)
        mission = _mission_dict(
            conn,
            conn.execute("SELECT * FROM life_missions WHERE id = ?", (mid,)).fetchone(),
        )
        dream_out = _row_dict(
            conn.execute("SELECT * FROM life_dreams WHERE id = ?", (dream_id,)).fetchone()
        )
        return {"mission": mission, "dream": dream_out}


# ─── Targets ─────────────────────────────────────────────────────────────────


def put_target(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    mission_id = str(fields.get("mission_id") or "").strip()
    if not mission_id:
        raise ValueError("mission_id required")
    tid = str(fields.get("id") or _new_id())
    title = str(fields.get("title") or "").strip()
    if not title:
        raise ValueError("title required")
    ttype = str(fields.get("target_type") or "essential")
    if ttype not in TARGET_TYPES:
        ttype = "essential"
    status = str(fields.get("status") or "not_started")
    if status not in TARGET_STATUSES:
        status = "not_started"
    with _conn() as conn:
        existing = conn.execute(
            "SELECT * FROM life_targets WHERE id = ?", (tid,)
        ).fetchone()
        if existing:
            seq = int(fields.get("sequence_number") or existing["sequence_number"])
            conn.execute(
                "UPDATE life_targets SET title=?, description=?, target_type=?, status=?, "
                "sequence_number=?, started_at=COALESCE(?, started_at), "
                "completed_at=?, updated_at=? WHERE id=?",
                (
                    title,
                    str(fields.get("description") or ""),
                    ttype,
                    status,
                    seq,
                    fields.get("started_at")
                    or (now if status == "in_progress" else None),
                    now if status == "complete" else fields.get("completed_at"),
                    now,
                    tid,
                ),
            )
            if status == "complete":
                _sync_focus(conn, mission_id)
        else:
            max_row = conn.execute(
                "SELECT COALESCE(MAX(sequence_number), 0) AS m FROM life_targets "
                "WHERE mission_id = ?",
                (mission_id,),
            ).fetchone()
            seq = int(fields.get("sequence_number") or max_row["m"] + 1)
            conn.execute(
                "INSERT INTO life_targets("
                "id, mission_id, sequence_number, title, description, target_type, "
                "status, focus_target, started_at, completed_at, created_at, updated_at) "
                "VALUES (?,?,?,?,?,?,?,0,?,?,?,?)",
                (
                    tid,
                    mission_id,
                    seq,
                    title,
                    str(fields.get("description") or ""),
                    ttype,
                    status,
                    now if status == "in_progress" else None,
                    now if status == "complete" else None,
                    now,
                    now,
                ),
            )
            _sync_focus(conn, mission_id)
        _validate_sequence(conn, mission_id)
        _export_primary_markdown(conn)
        row = conn.execute("SELECT * FROM life_targets WHERE id = ?", (tid,)).fetchone()
        return _row_dict(row)  # type: ignore[return-value]


def set_focus_target(mission_id: str, target_id: str | None) -> dict[str, Any]:
    with _conn() as conn:
        conn.execute(
            "UPDATE life_targets SET focus_target = 0 WHERE mission_id = ?",
            (mission_id,),
        )
        if target_id:
            conn.execute(
                "UPDATE life_targets SET focus_target = 1 WHERE id = ? AND mission_id = ?",
                (target_id, mission_id),
            )
        now = _utc_now()
        conn.execute(
            "INSERT INTO life_mission_state(mission_id, focus_target_id, "
            "completed_target_ids_json, checkpoint_json, updated_at) "
            "VALUES (?, ?, '[]', '{}', ?) "
            "ON CONFLICT(mission_id) DO UPDATE SET focus_target_id=excluded.focus_target_id, "
            "updated_at=excluded.updated_at",
            (mission_id, target_id, now),
        )
        state = conn.execute(
            "SELECT * FROM life_mission_state WHERE mission_id = ?",
            (mission_id,),
        ).fetchone()
        return _row_dict(state)  # type: ignore[return-value]


def validate_sequence(mission_id: str) -> dict[str, Any]:
    with _conn() as conn:
        warnings = _validate_sequence(conn, mission_id)
        targets = [
            _row_dict(r)
            for r in conn.execute(
                "SELECT * FROM life_targets WHERE mission_id = ? ORDER BY sequence_number",
                (mission_id,),
            ).fetchall()
        ]
        return {"warnings": warnings, "targets": targets}


# ─── Decisions / thoughts ────────────────────────────────────────────────────


def log_decision(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    did = str(fields.get("id") or _new_id())
    title = str(fields.get("title") or "").strip()
    if not title:
        raise ValueError("title required")
    options = fields.get("options")
    if not isinstance(options, list):
        options = []
    with _conn() as conn:
        conn.execute(
            "INSERT INTO life_decisions("
            "id, mission_id, target_id, title, context, options_json, chosen, "
            "human_said, ai_recommendation, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (
                did,
                fields.get("mission_id"),
                fields.get("target_id"),
                title,
                str(fields.get("context") or ""),
                json.dumps(options),
                str(fields.get("chosen") or ""),
                str(fields.get("human_said") or fields.get("humanSaid") or ""),
                str(
                    fields.get("ai_recommendation")
                    or fields.get("aiRecommendation")
                    or ""
                ),
                now,
            ),
        )
        mid = fields.get("mission_id")
        if mid:
            conn.execute(
                "INSERT INTO life_mission_state(mission_id, last_decision_id, "
                "completed_target_ids_json, checkpoint_json, updated_at) "
                "VALUES (?, ?, '[]', '{}', ?) "
                "ON CONFLICT(mission_id) DO UPDATE SET "
                "last_decision_id=excluded.last_decision_id, updated_at=excluded.updated_at",
                (mid, did, now),
            )
        row = conn.execute("SELECT * FROM life_decisions WHERE id = ?", (did,)).fetchone()
        d = _row_dict(row)
        assert d is not None
        try:
            d["options"] = json.loads(d.pop("options_json") or "[]")
        except json.JSONDecodeError:
            d["options"] = []
        return d


def list_decisions(*, mission_id: str | None = None, limit: int = 50) -> list[dict[str, Any]]:
    with _conn() as conn:
        if mission_id:
            rows = conn.execute(
                "SELECT * FROM life_decisions WHERE mission_id = ? "
                "ORDER BY created_at DESC LIMIT ?",
                (mission_id, limit),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM life_decisions ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        out = []
        for r in rows:
            d = _row_dict(r)
            assert d is not None
            try:
                d["options"] = json.loads(d.pop("options_json") or "[]")
            except json.JSONDecodeError:
                d["options"] = []
            out.append(d)
        return out


# ─── Documents ───────────────────────────────────────────────────────────────


def put_document(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    mission_id = str(fields.get("mission_id") or "").strip()
    if not mission_id:
        # Default to Primary so Focus write-ups land under a mission even if
        # the model omits mission_id.
        try:
            primary = get_stack().get("primary") or {}
            mission_id = str(primary.get("id") or "").strip()
        except Exception:
            mission_id = ""
    if not mission_id:
        raise ValueError("mission_id required (or set a Primary Mission first)")
    title = str(fields.get("title") or "").strip()
    if not title:
        raise ValueError("title required")
    did = str(fields.get("id") or _new_id())
    doc_type = str(fields.get("doc_type") or fields.get("type") or "other").strip().lower()
    if doc_type not in DOC_TYPES:
        doc_type = "other"
    source = str(fields.get("source") or "agent").strip().lower()
    if source not in DOC_SOURCES:
        source = "agent"
    summary = str(fields.get("summary") or "").strip()
    body_md = str(fields.get("body_md") or fields.get("body") or fields.get("content") or "")
    if not summary and body_md.strip():
        summary = " ".join(body_md.strip().split())[:160]
    target_id = fields.get("target_id")
    target_id = str(target_id).strip() if target_id else None
    plan_id = fields.get("plan_id")
    plan_id = str(plan_id).strip() if plan_id else None
    announce = fields.get("announce", True)
    with _conn() as conn:
        existing = conn.execute(
            "SELECT id FROM life_documents WHERE id = ?", (did,)
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE life_documents SET mission_id=?, target_id=?, title=?, doc_type=?, "
                "summary=?, body_md=?, plan_id=?, source=?, updated_at=? WHERE id=?",
                (
                    mission_id,
                    target_id,
                    title,
                    doc_type,
                    summary,
                    body_md,
                    plan_id,
                    source,
                    now,
                    did,
                ),
            )
        else:
            conn.execute(
                "INSERT INTO life_documents("
                "id, mission_id, target_id, title, doc_type, summary, body_md, plan_id, "
                "source, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (
                    did,
                    mission_id,
                    target_id,
                    title,
                    doc_type,
                    summary,
                    body_md,
                    plan_id,
                    source,
                    now,
                    now,
                ),
            )
        row = conn.execute("SELECT * FROM life_documents WHERE id = ?", (did,)).fetchone()
        out = _row_dict(row)
        assert out is not None
        bump_data_version(conn)

    # Pulse TV / Focus thought stream only after a real save.
    if announce is not False:
        try:
            post_thought(
                {
                    "mission_id": mission_id,
                    "target_id": target_id,
                    "activity_type": "artifact",
                    "summary": f"Saved document: {title}",
                    "detail": summary or f"doc_type={doc_type}",
                }
            )
        except Exception:
            pass
    return out


def get_document(document_id: str) -> dict[str, Any] | None:
    did = str(document_id or "").strip()
    if not did:
        return None
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM life_documents WHERE id = ?", (did,)
        ).fetchone()
        return _row_dict(row)


def assign_document(
    document_id: str,
    mission_id: str,
    *,
    announce: bool = False,
) -> dict[str, Any]:
    """Move a document to another mission without wiping title/body."""
    did = str(document_id or "").strip()
    mid = str(mission_id or "").strip()
    if not did:
        raise ValueError("document_id required")
    if not mid:
        raise ValueError("mission_id required")
    mission = get_mission(mid)
    if not mission or not mission.get("id"):
        raise ValueError(f"mission not found: {mid}")
    now = _utc_now()
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM life_documents WHERE id = ?", (did,)
        ).fetchone()
        if row is None:
            raise ValueError(f"document not found: {did}")
        conn.execute(
            "UPDATE life_documents SET mission_id = ?, updated_at = ? WHERE id = ?",
            (mid, now, did),
        )
        bump_data_version(conn)
        out_row = conn.execute(
            "SELECT * FROM life_documents WHERE id = ?", (did,)
        ).fetchone()
        out = _row_dict(out_row)
        assert out is not None

    if announce:
        try:
            post_thought(
                {
                    "mission_id": mid,
                    "activity_type": "artifact",
                    "summary": f"Assigned document: {out.get('title') or did}",
                    "detail": f"Moved to mission {mid}",
                }
            )
        except Exception:
            pass
    return out


def rehome_primary_import_orphans() -> dict[str, Any]:
    """Move unmatched Primary Scan dumps into Document library (schema v4).

    Keeps an import on Primary only when soft-match would still pick Primary.
    Idempotent via ``life_meta.rehome_primary_imports_v4``.
    Uses a dedicated connection (not ``_conn``) so schema warm hooks cannot
    recurse into this function mid-flight.
    """
    path = str(life_db_path())
    conn = sqlite3.connect(path, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        ensure_schema(conn)
        done = conn.execute(
            "SELECT value FROM life_meta WHERE key = 'rehome_primary_imports_v4'"
        ).fetchone()
        if done is not None and str(done["value"]) == "1":
            return {"moved": 0, "kept": 0, "skipped": True}

        stack_row = conn.execute(
            "SELECT primary_mission_id FROM life_mission_stack WHERE id = 1"
        ).fetchone()
        primary_id = ""
        if stack_row and stack_row["primary_mission_id"]:
            primary_id = str(stack_row["primary_mission_id"]).strip()
        if not primary_id:
            prow = conn.execute(
                "SELECT id FROM life_missions WHERE mission_type = 'primary' "
                "ORDER BY created_at LIMIT 1"
            ).fetchone()
            if prow:
                primary_id = str(prow["id"]).strip()
        if not primary_id:
            conn.execute(
                "INSERT OR REPLACE INTO life_meta(key, value) "
                "VALUES ('rehome_primary_imports_v4', '1')"
            )
            conn.commit()
            return {"moved": 0, "kept": 0, "skipped": True}

        # Ensure library exists (may open nested work — guarded by in-progress).
        library_id = ensure_document_library_mission()

        rows = conn.execute(
            "SELECT * FROM life_documents WHERE mission_id = ? AND source = 'import' "
            "AND (id LIKE 'import:%' OR id LIKE 'plan:%' OR id LIKE 'outcome:%')",
            (primary_id,),
        ).fetchall()
        docs = [_row_dict(r) for r in rows]

        primary_title = ""
        prow = conn.execute(
            "SELECT title FROM life_missions WHERE id = ?", (primary_id,)
        ).fetchone()
        if prow:
            primary_title = str(prow["title"] or "").strip().lower()

        to_move: list[str] = []
        kept = 0
        for doc in docs:
            if not doc:
                continue
            hint = " ".join(
                [
                    str(doc.get("title") or ""),
                    str(doc.get("summary") or ""),
                    str(doc.get("body_md") or "")[:500],
                ]
            ).lower()
            # Keep only when the Primary title itself appears (strong match).
            # Token soft-match is too loose for migration ("mission" alone).
            if primary_title and primary_title in hint:
                kept += 1
            else:
                did = str(doc.get("id") or "").strip()
                if did:
                    to_move.append(did)

        now = _utc_now()
        for did in to_move:
            conn.execute(
                "UPDATE life_documents SET mission_id = ?, updated_at = ? WHERE id = ?",
                (library_id, now, did),
            )
        if to_move:
            bump_data_version(conn)
        conn.execute(
            "INSERT OR REPLACE INTO life_meta(key, value) "
            "VALUES ('rehome_primary_imports_v4', '1')"
        )
        conn.commit()
        return {"moved": len(to_move), "kept": kept, "skipped": False}
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def list_documents(
    *,
    mission_id: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    lim = max(1, min(int(limit or 50), 200))
    with _conn() as conn:
        if mission_id:
            rows = conn.execute(
                "SELECT * FROM life_documents WHERE mission_id = ? "
                "ORDER BY updated_at DESC LIMIT ?",
                (str(mission_id), lim),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM life_documents ORDER BY updated_at DESC LIMIT ?",
                (lim,),
            ).fetchall()
        return [_row_dict(r) for r in rows]  # type: ignore[misc]


def search_documents(
    query: str,
    *,
    source: str | None = None,
    mission_id: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Search title/summary/body via FTS5 MATCH; Python substring fallback."""
    q_raw = str(query or "").strip()
    fts_query = _sanitize_fts_query(q_raw) if q_raw else ""
    # Prefer sanitized terms for substring fallback when the raw query is noisy.
    q = (fts_query or q_raw).lower()
    lim = max(1, min(int(limit or 50), 200))
    src = str(source or "").strip().lower() or None
    if src and src not in DOC_SOURCES:
        src = None
    mid = str(mission_id).strip() if mission_id else None

    def _shape_rows(rows: list[Any]) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for row in rows:
            d = _row_dict(row)
            if d is None:
                continue
            mission_title = d.pop("mission_title", None)
            mission_statement = d.pop("mission_statement", None)
            d["mission_title"] = (
                (mission_title or mission_statement or "").strip() or None
            )
            body = str(d.get("body_md") or "")
            if len(body) > 400:
                d["body_md"] = body[:399].rstrip() + "…"
                d["body_truncated"] = True
            else:
                d["body_truncated"] = False
            d["excerpt"] = document_excerpt(d, max_chars=280)
            out.append(d)
            if len(out) >= lim:
                break
        return out

    def _python_filter(rows: list[Any]) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for row in rows:
            d = _row_dict(row)
            if d is None:
                continue
            mission_title = d.pop("mission_title", None)
            mission_statement = d.pop("mission_statement", None)
            d["mission_title"] = (
                (mission_title or mission_statement or "").strip() or None
            )
            if q:
                hay = " ".join(
                    [
                        str(d.get("title") or ""),
                        str(d.get("summary") or ""),
                        str(d.get("body_md") or ""),
                        str(d.get("doc_type") or ""),
                    ]
                ).lower()
                terms = [t for t in q.split() if len(t) > 1] or [q]
                if q not in hay and not any(t in hay for t in terms):
                    continue
            body = str(d.get("body_md") or "")
            if len(body) > 400:
                d["body_md"] = body[:399].rstrip() + "…"
                d["body_truncated"] = True
            else:
                d["body_truncated"] = False
            d["excerpt"] = document_excerpt(d, max_chars=280)
            out.append(d)
            if len(out) >= lim:
                break
        return out

    with _conn() as conn:
        base_select = (
            "SELECT d.*, m.title AS mission_title, m.statement AS mission_statement "
            "FROM life_documents d "
            "LEFT JOIN life_missions m ON m.id = d.mission_id "
        )
        filters = ""
        params: list[Any] = []
        if mid:
            filters += " AND d.mission_id = ?"
            params.append(mid)
        if src:
            filters += " AND d.source = ?"
            params.append(src)

        if fts_query:
            try:
                fts_sql = (
                    base_select
                    + "JOIN life_documents_fts f ON f.doc_id = d.id "
                    + "WHERE f MATCH ?"
                    + filters
                    + " ORDER BY d.updated_at DESC LIMIT ?"
                )
                fts_params = [fts_query, *params, lim]
                rows = conn.execute(fts_sql, fts_params).fetchall()
                if rows:
                    return _shape_rows(rows)
            except sqlite3.Error:
                pass

        sql = base_select + "WHERE 1=1" + filters + " ORDER BY d.updated_at DESC LIMIT ?"
        # Over-fetch when filtering by query in Python.
        rows = conn.execute(sql, [*params, lim * 4 if q else lim]).fetchall()
        return _python_filter(rows)


def document_excerpt(doc: dict[str, Any], *, max_chars: int = 400) -> str:
    body = str(doc.get("body_md") or "").strip()
    summary = str(doc.get("summary") or "").strip()
    text = body or summary
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1].rstrip() + "…"


# ─── Legacy / filesystem document import ─────────────────────────────────────

_SCAN_TEXT_SUFFIXES = frozenset({".md", ".markdown", ".txt", ".rst"})
_SCAN_SKIP_DIRS = frozenset(
    {
        "node_modules",
        ".git",
        "venv",
        ".venv",
        "target",
        "__pycache__",
        ".cache",
        "Library",
        ".local",
        ".cargo",
        ".npm",
        ".centurion",  # avoid walking home recursively into itself via cwd
        "Centurion-AI-OS",  # monorepo — thousands of md files, not user memos
        "dist",
        "build",
        ".tox",
    }
)
_MAX_IMPORT_FILE_BYTES = int(1.5 * 1024 * 1024)
_MAX_SCAN_FILES = 2000
_MAX_SCAN_DEPTH = 8


def _stable_import_id(kind: str, key: str) -> str:
    digest = hashlib.sha256(f"{kind}:{key}".encode("utf-8")).hexdigest()[:32]
    return f"{kind}:{digest}"


def _slug_tokens(text: str) -> list[str]:
    return [t for t in re.split(r"[^a-z0-9]+", (text or "").lower()) if len(t) > 2]


def _doc_type_from_name(name: str) -> str:
    n = (name or "").lower()
    if "research" in n or "memo" in n or "brief" in n:
        return "research"
    if "analys" in n:
        return "analysis"
    if "report" in n or "summary" in n:
        return "report"
    if "plan" in n:
        return "plan"
    if "content" in n or "draft" in n or "post" in n:
        return "content"
    return "other"


def _terminal_cwd_from_config() -> Path | None:
    try:
        from centurion_cli.config import load_config

        cfg = load_config()
        terminal = cfg.get("terminal") if isinstance(cfg, dict) else None
        cwd = None
        if isinstance(terminal, dict):
            cwd = terminal.get("cwd")
        if isinstance(cwd, str) and cwd.strip():
            path = Path(cwd).expanduser()
            if path.is_dir():
                return path.resolve()
    except Exception:
        pass
    return None


def default_document_scan_roots() -> list[Path]:
    """Default filesystem roots to scan for legacy text documents."""
    roots: list[Path] = []
    home = Path.home()
    for name in ("Documents", "Desktop", "centurion"):
        candidate = home / name
        if candidate.is_dir():
            roots.append(candidate.resolve())
    # Titus Brain historical workspace (Legio account).
    for explicit in (
        Path("/home/Legio/centurion"),
        Path.home() / "centurion",
    ):
        try:
            if explicit.is_dir():
                roots.append(explicit.resolve())
        except OSError:
            pass
    cwd = _terminal_cwd_from_config()
    if cwd is not None:
        roots.append(cwd)
    extra = os.environ.get("CENTURION_DOC_SCAN_PATHS") or ""
    for part in extra.split(os.pathsep):
        part = part.strip()
        if not part:
            continue
        path = Path(part).expanduser()
        if path.is_dir():
            roots.append(path.resolve())
    # Dedupe while preserving order.
    seen: set[str] = set()
    out: list[Path] = []
    for root in roots:
        key = str(root)
        if key in seen:
            continue
        seen.add(key)
        out.append(root)
    return out


def scan_filesystem_documents(
    roots: list[Path] | None = None,
    *,
    max_files: int = _MAX_SCAN_FILES,
    max_depth: int = _MAX_SCAN_DEPTH,
) -> list[dict[str, Any]]:
    """Walk roots for text documents (md/txt/rst). Does not read bodies yet."""
    scan_roots = list(roots) if roots is not None else default_document_scan_roots()
    lim = max(1, min(int(max_files or _MAX_SCAN_FILES), 5000))
    depth_lim = max(1, min(int(max_depth or _MAX_SCAN_DEPTH), 32))
    found: list[dict[str, Any]] = []
    for root in scan_roots:
        try:
            root = Path(root).expanduser().resolve()
        except OSError:
            continue
        if not root.is_dir():
            continue
        root_depth = len(root.parts)
        for dirpath, dirnames, filenames in os.walk(root):
            try:
                cur_depth = len(Path(dirpath).parts) - root_depth
            except Exception:
                cur_depth = 0
            if cur_depth >= depth_lim:
                dirnames[:] = []
                continue
            dirnames[:] = [
                d
                for d in dirnames
                if d not in _SCAN_SKIP_DIRS and not d.startswith(".")
            ]
            for name in filenames:
                if len(found) >= lim:
                    return found
                path = Path(dirpath) / name
                suffix = path.suffix.lower()
                if suffix not in _SCAN_TEXT_SUFFIXES:
                    continue
                try:
                    size = path.stat().st_size
                except OSError:
                    continue
                if size <= 0 or size > _MAX_IMPORT_FILE_BYTES:
                    continue
                found.append(
                    {
                        "path": str(path),
                        "title": path.stem.replace("_", " ").replace("-", " ").strip()
                        or path.name,
                        "size": size,
                        "suffix": suffix,
                    }
                )
    return found


DOCUMENT_LIBRARY_MISSION_ID = "mission:document-library"


def ensure_document_library_mission() -> str:
    """Hidden supporting mission for imports that do not match a real mission."""
    existing = get_mission(DOCUMENT_LIBRARY_MISSION_ID)
    if existing and existing.get("id"):
        return DOCUMENT_LIBRARY_MISSION_ID
    put_mission(
        {
            "id": DOCUMENT_LIBRARY_MISSION_ID,
            "title": "Document library",
            "statement": (
                "Imported write-ups not yet tied to a specific mission. "
                "Search them with Find documents on Focus."
            ),
            "mission_type": "supporting",
            "phase": "discovery",
            "status": "active",
            "stack_sort_order": 10_000,
            "profile": {
                "system": True,
                "hidden_from_stack": True,
            },
        }
    )
    return DOCUMENT_LIBRARY_MISSION_ID


def _resolve_import_mission_id(
    *,
    preferred_mission_id: str | None,
    hint_text: str,
    unmatched: str = "library",
) -> str | None:
    """Pick a mission for an imported document.

    Strong title/path matches win. Unmatched docs go to the Document library by
    default so Primary / supporting mission Documents stay mission-scoped —
    never dump the whole scan onto Primary. Pass ``unmatched=\"preferred\"``
    when the caller explicitly forced ``--mission-id``.
    """
    hint = (hint_text or "").lower()
    hint_tokens = set(_slug_tokens(hint_text))
    missions = list_missions()
    best_id = ""
    best_score = 0
    for mission in missions:
        mid = str(mission.get("id") or "").strip()
        title = str(mission.get("title") or "").strip()
        if not mid or not title:
            continue
        # Never soft-match the system library itself.
        if mid == DOCUMENT_LIBRARY_MISSION_ID:
            continue
        profile = mission.get("profile") if isinstance(mission.get("profile"), dict) else {}
        if profile.get("hidden_from_stack") or profile.get("system"):
            continue
        title_l = title.lower()
        score = 0
        if title_l and title_l in hint:
            score += 10 + len(title_l)
        title_tokens = set(_slug_tokens(title))
        overlap = len(title_tokens & hint_tokens)
        if overlap:
            score += overlap * 3
        # Prefer supporting matches slightly when scores tie on Centurion AI Limited etc.
        if mission.get("mission_type") == "supporting" and score > 0:
            score += 1
        if score > best_score:
            best_score = score
            best_id = mid
    if best_id and best_score >= 3:
        return best_id

    mode = str(unmatched or "library").strip().lower()
    if mode == "preferred":
        preferred = str(preferred_mission_id or "").strip()
        if preferred:
            mission = get_mission(preferred)
            if mission and mission.get("id"):
                return str(mission["id"])
        stack = get_stack()
        primary = stack.get("primary") or {}
        pid = str(primary.get("id") or "").strip()
        if pid:
            return pid
        if missions:
            return str(missions[0].get("id") or "").strip()
        raise ValueError("No Life Mission available to attach imported documents")

    if mode == "skip":
        return None

    return ensure_document_library_mission()


def _import_one_document(fields: dict[str, Any]) -> str:
    """put_document with announce off. Returns 'imported' or 'updated'."""
    did = str(fields.get("id") or "").strip()
    existed = bool(did and get_document(did))
    put_document({**fields, "announce": False})
    return "updated" if existed else "imported"


def _import_filesystem_hits(
    hits: list[dict[str, Any]],
    *,
    mission_id: str | None,
    unmatched: str = "library",
) -> tuple[int, int, int, list[str]]:
    imported = updated = skipped = 0
    errors: list[str] = []
    for hit in hits:
        path_s = str(hit.get("path") or "")
        path = Path(path_s)
        try:
            body = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            skipped += 1
            errors.append(f"{path_s}: {exc}")
            continue
        if not body.strip():
            skipped += 1
            continue
        title = str(hit.get("title") or path.stem).strip() or path.name
        try:
            mid = _resolve_import_mission_id(
                preferred_mission_id=mission_id,
                hint_text=f"{path_s} {title}",
                unmatched=unmatched,
            )
            if not mid:
                skipped += 1
                continue
            status = _import_one_document(
                {
                    "id": _stable_import_id("import", str(path.resolve())),
                    "mission_id": mid,
                    "title": title[:200],
                    "doc_type": _doc_type_from_name(title),
                    "summary": f"Imported from: {path_s}",
                    "body_md": body,
                    "source": "import",
                }
            )
            if status == "imported":
                imported += 1
            else:
                updated += 1
        except Exception as exc:
            skipped += 1
            errors.append(f"{path_s}: {exc}")
    return imported, updated, skipped, errors


def _import_plans(
    *, mission_id: str | None, unmatched: str = "library"
) -> tuple[int, int, int, list[str]]:
    imported = updated = skipped = 0
    errors: list[str] = []
    try:
        from centurion_cli.plans import get_plan, list_plans
    except Exception as exc:
        return 0, 0, 0, [f"plans unavailable: {exc}"]

    try:
        plans = list_plans()
    except Exception as exc:
        return 0, 0, 0, [f"list_plans failed: {exc}"]

    for entry in plans:
        pid = str(entry.get("id") or "").strip()
        if not pid:
            skipped += 1
            continue
        try:
            plan = get_plan(pid) or entry
            title = str(plan.get("title") or entry.get("title") or "Plan").strip()
            goal = str(plan.get("goal") or "").strip()
            summary = str(plan.get("summary") or "").strip()
            steps = plan.get("steps") or []
            if not isinstance(steps, list):
                steps = []
            step_lines = "\n".join(
                f"- {s}" for s in steps if isinstance(s, str) and s.strip()
            )
            body_parts = [
                f"# {title}",
                f"**Goal:** {goal}" if goal else "",
                summary,
                "## Steps\n" + step_lines if step_lines else "",
            ]
            body = "\n\n".join(p for p in body_parts if p)
            if not body.strip():
                skipped += 1
                continue
            mid = _resolve_import_mission_id(
                preferred_mission_id=mission_id,
                hint_text=f"{title} {goal} {summary}",
                unmatched=unmatched,
            )
            if not mid:
                skipped += 1
                continue
            status = _import_one_document(
                {
                    "id": _stable_import_id("plan", pid),
                    "mission_id": mid,
                    "title": title[:200],
                    "doc_type": "plan",
                    "summary": f"Imported from: plan:{pid}"
                    + (f" — {summary[:120]}" if summary else ""),
                    "body_md": body,
                    "plan_id": pid,
                    "source": "import",
                }
            )
            if status == "imported":
                imported += 1
            else:
                updated += 1
        except Exception as exc:
            skipped += 1
            errors.append(f"plan:{pid}: {exc}")
    return imported, updated, skipped, errors


def _import_kanban_outcomes(
    *, mission_id: str | None, unmatched: str = "library"
) -> tuple[int, int, int, list[str]]:
    imported = updated = skipped = 0
    errors: list[str] = []
    try:
        from centurion_cli.swarm_state import get_swarm_snapshot

        snap = get_swarm_snapshot()
    except Exception as exc:
        return 0, 0, 0, [f"swarm snapshot unavailable: {exc}"]

    outcomes = snap.get("outcomes") if isinstance(snap, dict) else None
    if not isinstance(outcomes, list):
        return 0, 0, 0, []

    for outcome in outcomes:
        if not isinstance(outcome, dict):
            skipped += 1
            continue
        oid = str(outcome.get("id") or "").strip()
        body = str(outcome.get("description") or outcome.get("result") or "").strip()
        if not oid or not body:
            skipped += 1
            continue
        title = str(
            outcome.get("title")
            or outcome.get("summary")
            or body.split("\n", 1)[0][:80]
            or "Task outcome"
        ).strip()
        try:
            mid = _resolve_import_mission_id(
                preferred_mission_id=mission_id,
                hint_text=f"{title} {body[:400]}",
                unmatched=unmatched,
            )
            if not mid:
                skipped += 1
                continue
            status = _import_one_document(
                {
                    "id": _stable_import_id("outcome", oid),
                    "mission_id": mid,
                    "title": title[:200],
                    "doc_type": "other",
                    "summary": f"Imported from: outcome:{oid}",
                    "body_md": body,
                    "source": "import",
                }
            )
            if status == "imported":
                imported += 1
            else:
                updated += 1
        except Exception as exc:
            skipped += 1
            errors.append(f"outcome:{oid}: {exc}")
    return imported, updated, skipped, errors


def import_scanned_documents(
    *,
    roots: list[str | Path] | None = None,
    mission_id: str | None = None,
    force_mission: bool = False,
    include_plans: bool = True,
    include_outcomes: bool = True,
    max_files: int = _MAX_SCAN_FILES,
) -> dict[str, Any]:
    """Scan filesystem (+ optional plans/outcomes) into life_documents.

    Idempotent via stable ids (``import:<hash>``, ``plan:<hash>``, ``outcome:<hash>``).
    Never raises — soft-fails into ``errors`` so Focus Scan always gets a payload.

    Unmatched files attach to the hidden Document library unless ``force_mission``
    is set (CLI ``--mission-id``), so mission Documents lists stay scoped.
    """
    unmatched = "preferred" if (force_mission and mission_id) else "library"
    path_roots: list[Path] | None
    root_display: list[str] = []
    try:
        if roots is None:
            path_roots = None
            root_display = [str(p) for p in default_document_scan_roots()]
        else:
            path_roots = []
            for r in roots:
                try:
                    path_roots.append(Path(r).expanduser().resolve())
                except OSError:
                    continue
            root_display = [str(p) for p in path_roots]

        imported = updated = skipped = 0
        errors: list[str] = []
        hits: list[dict[str, Any]] = []

        hits = scan_filesystem_documents(path_roots, max_files=max_files)
        i, u, s, errs = _import_filesystem_hits(
            hits, mission_id=mission_id, unmatched=unmatched
        )
        imported += i
        updated += u
        skipped += s
        errors.extend(errs)

        if include_plans:
            i, u, s, errs = _import_plans(
                mission_id=mission_id, unmatched=unmatched
            )
            imported += i
            updated += u
            skipped += s
            errors.extend(errs)

        if include_outcomes:
            i, u, s, errs = _import_kanban_outcomes(
                mission_id=mission_id, unmatched=unmatched
            )
            imported += i
            updated += u
            skipped += s
            errors.extend(errs)

        return {
            "imported": imported,
            "updated": updated,
            "skipped": skipped,
            "scanned_files": len(hits),
            "roots": root_display,
            "errors": errors[:40],
        }
    except Exception as exc:
        return {
            "imported": 0,
            "updated": 0,
            "skipped": 0,
            "scanned_files": 0,
            "roots": root_display,
            "errors": [str(exc).strip() or type(exc).__name__],
        }


def post_thought(fields: dict[str, Any]) -> dict[str, Any]:
    now = _utc_now()
    tid = str(fields.get("id") or _new_id())
    summary = str(fields.get("summary") or "").strip()
    if not summary:
        raise ValueError("summary required")
    activity = str(fields.get("activity_type") or fields.get("activityType") or "thought")
    if activity not in THOUGHT_TYPES:
        activity = "thought"
    with _conn() as conn:
        conn.execute(
            "INSERT INTO life_thoughts("
            "id, mission_id, target_id, activity_type, summary, detail, progress, created_at) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (
                tid,
                fields.get("mission_id"),
                fields.get("target_id"),
                activity,
                summary,
                str(fields.get("detail") or ""),
                fields.get("progress"),
                now,
            ),
        )
        bump_data_version(conn)
        row = conn.execute("SELECT * FROM life_thoughts WHERE id = ?", (tid,)).fetchone()
        return _row_dict(row)  # type: ignore[return-value]


def list_thoughts(*, since: str | None = None, limit: int = 50) -> list[dict[str, Any]]:
    with _conn() as conn:
        if since:
            rows = conn.execute(
                "SELECT * FROM life_thoughts WHERE created_at > ? "
                "ORDER BY created_at DESC LIMIT ?",
                (since, limit),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM life_thoughts ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [_row_dict(r) for r in rows]  # type: ignore[misc]


def cleanup_thoughts(older_than_hours: int = 24) -> int:
    cutoff = datetime.now(timezone.utc).timestamp() - older_than_hours * 3600
    cutoff_iso = (
        datetime.fromtimestamp(cutoff, tz=timezone.utc).replace(microsecond=0).isoformat()
    )
    with _conn() as conn:
        cur = conn.execute(
            "DELETE FROM life_thoughts WHERE created_at < ?",
            (cutoff_iso,),
        )
        return cur.rowcount


# ─── Context ─────────────────────────────────────────────────────────────────


def resolve_context(query: str) -> list[dict[str, Any]]:
    q = query.strip().lower()
    if not q:
        return []
    terms = [t for t in q.split() if len(t) > 2] or [q]
    matches: list[dict[str, Any]] = []
    with _conn() as conn:
        subjects = {
            r["id"]: r for r in conn.execute("SELECT * FROM life_subjects").fetchall()
        }
        missions = conn.execute("SELECT * FROM life_missions").fetchall()
        for mission in missions:
            subject = subjects.get(mission["subject_id"]) if mission["subject_id"] else None
            hay = " ".join(
                [
                    mission["title"] or "",
                    mission["statement"] or "",
                    mission["why"] or "",
                    mission["purpose"] or "",
                    mission["situation"] or "",
                ]
            ).lower()
            for term in terms:
                if term in hay:
                    field = (
                        "mission.title"
                        if term in (mission["title"] or "").lower()
                        else "mission"
                    )
                    matches.append(
                        {
                            "subject": (
                                {"id": subject["id"], "name": subject["name"]}
                                if subject
                                else None
                            ),
                            "mission": {
                                "id": mission["id"],
                                "name": mission["title"] or mission["statement"],
                                "phase": mission["phase"],
                            },
                            "target": None,
                            "confidence": 0.7,
                            "matched_field": field,
                            "matched_term": term,
                        }
                    )
            targets = conn.execute(
                "SELECT * FROM life_targets WHERE mission_id = ?",
                (mission["id"],),
            ).fetchall()
            for target in targets:
                ttitle = (target["title"] or "").lower()
                for term in terms:
                    if term in ttitle:
                        matches.append(
                            {
                                "subject": (
                                    {"id": subject["id"], "name": subject["name"]}
                                    if subject
                                    else None
                                ),
                                "mission": {
                                    "id": mission["id"],
                                    "name": mission["title"] or mission["statement"],
                                    "phase": mission["phase"],
                                },
                                "target": {
                                    "id": target["id"],
                                    "sequence": target["sequence_number"],
                                    "title": target["title"],
                                    "type": target["target_type"],
                                },
                                "confidence": 0.89,
                                "matched_field": "target.title",
                                "matched_term": term,
                            }
                        )
            docs = conn.execute(
                "SELECT id, title, summary, doc_type, body_md FROM life_documents "
                "WHERE mission_id = ?",
                (mission["id"],),
            ).fetchall()
            for doc in docs:
                body = doc["body_md"] or ""
                body_excerpt = body[:400] if body else ""
                hay = " ".join(
                    [
                        doc["title"] or "",
                        doc["summary"] or "",
                        doc["doc_type"] or "",
                        body_excerpt,
                    ]
                ).lower()
                for term in terms:
                    if term in hay:
                        matched_field = "document"
                        if term in (doc["title"] or "").lower():
                            matched_field = "document.title"
                        elif term in body_excerpt.lower():
                            matched_field = "document.body"
                        elif term in (doc["summary"] or "").lower():
                            matched_field = "document.summary"
                        matches.append(
                            {
                                "subject": (
                                    {"id": subject["id"], "name": subject["name"]}
                                    if subject
                                    else None
                                ),
                                "mission": {
                                    "id": mission["id"],
                                    "name": mission["title"] or mission["statement"],
                                    "phase": mission["phase"],
                                },
                                "target": None,
                                "document": {
                                    "id": doc["id"],
                                    "title": doc["title"],
                                    "doc_type": doc["doc_type"],
                                    "summary": doc["summary"] or "",
                                    "excerpt": body_excerpt[:280] if body_excerpt else (
                                        doc["summary"] or ""
                                    ),
                                },
                                "confidence": 0.82
                                if matched_field == "document.body"
                                else 0.78,
                                "matched_field": matched_field,
                                "matched_term": term,
                            }
                        )
    matches.sort(key=lambda m: m["confidence"], reverse=True)
    return matches[:10]


def inject_context(
    message: str,
    current_view: dict[str, Any] | None = None,
) -> dict[str, Any]:
    current_view = current_view or {}
    mission_id = current_view.get("mission_id")
    target_id = current_view.get("target_id")
    subject_id = current_view.get("subject_id")
    document_ids = current_view.get("document_ids") or []
    if isinstance(document_ids, str):
        document_ids = [document_ids]
    if not isinstance(document_ids, list):
        document_ids = []
    if not mission_id:
        matches = resolve_context(message)
        if matches:
            mission_id = matches[0]["mission"]["id"]
            target_id = (matches[0].get("target") or {}).get("id")
            subject_id = (matches[0].get("subject") or {}).get("id")
            doc_match = matches[0].get("document") or {}
            if doc_match.get("id") and not document_ids:
                document_ids = [doc_match["id"]]

    # Load without nested _conn() — SQLite locks when one write txn is open.
    mission = get_mission(str(mission_id)) if mission_id else None
    subject = None
    sid = subject_id or (mission or {}).get("subject_id")
    if sid:
        for s in list_subjects():
            if s.get("id") == sid:
                subject = s
                break
    targets = (mission or {}).get("targets") or []
    target = next((t for t in targets if t and t.get("id") == target_id), None)
    if target is None:
        target = next((t for t in targets if t and t.get("focus_target")), None)
    decisions = list_decisions(mission_id=str(mission_id) if mission_id else None, limit=1)
    thoughts = list_thoughts(limit=3)
    docs = list_documents(mission_id=str(mission_id) if mission_id else None, limit=8)
    # Pin explicitly requested documents (Discuss) at the front.
    pinned: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw_id in document_ids:
        did = str(raw_id or "").strip()
        if not did or did in seen:
            continue
        seen.add(did)
        doc = get_document(did)
        if doc:
            pinned.append(doc)
            if not mission_id and doc.get("mission_id"):
                mission_id = doc["mission_id"]
                if mission is None:
                    mission = get_mission(str(mission_id))
    for doc in docs:
        did = str(doc.get("id") or "")
        if did and did not in seen:
            pinned.append(doc)
            seen.add(did)
    docs = pinned[:5]
    last_decision = decisions[0] if decisions else None
    subject_name = (subject or {}).get("name") or "Uncategorised"
    mission_name = (
        (mission or {}).get("title") or (mission or {}).get("statement") or "Mission"
    )
    phase = (mission or {}).get("phase") or "executing"
    parts = [f"Subject: {subject_name}", f"Mission: {mission_name} ({phase})"]
    if target:
        parts.append(
            f"Target {target.get('sequence_number')}/{len(targets)}: {target.get('title')}"
        )
    lines = [" > ".join(parts)]
    if last_decision:
        lines.append(
            f"Last decision: {last_decision.get('chosen') or last_decision.get('title')}"
        )
    if thoughts:
        lines.append(f"Recent: {thoughts[0].get('summary')}")
    if docs:
        lines.append("Available documents:")
        for doc in docs:
            excerpt = document_excerpt(doc, max_chars=280)
            dtype = doc.get("doc_type") or "other"
            title = doc.get("title") or "Untitled"
            lines.append(f"- [{dtype}] {title} (id={doc.get('id')}): {excerpt}")
    return {
        "resolved_context": {
            "subject": (
                {"id": subject["id"], "name": subject["name"]} if subject else None
            ),
            "mission": (
                {
                    "id": mission["id"],
                    "name": mission_name,
                    "phase": phase,
                    "focus_target": (target or {}).get("sequence_number"),
                }
                if mission
                else None
            ),
            "target": (
                {
                    "id": target["id"],
                    "sequence": target.get("sequence_number"),
                    "title": target.get("title"),
                }
                if target
                else None
            ),
            "documents": [
                {
                    "id": d.get("id"),
                    "title": d.get("title"),
                    "doc_type": d.get("doc_type"),
                    "summary": d.get("summary") or "",
                    "excerpt": document_excerpt(d, max_chars=280),
                    "plan_id": d.get("plan_id"),
                    "updated_at": d.get("updated_at"),
                }
                for d in docs
            ],
            "state": {
                "completed_targets": (
                    (mission or {}).get("state", {}).get("completed_target_ids", [])
                    if mission
                    else []
                ),
                "last_decision": (last_decision or {}).get("chosen")
                or (last_decision or {}).get("title"),
            },
            "recent_activity": [
                {
                    "type": t.get("activity_type"),
                    "summary": t.get("summary"),
                    "time": t.get("created_at"),
                }
                for t in thoughts
            ],
        },
        "formatted_for_ai": "\n".join(lines),
    }


def snapshot_extras(*, since: str | None = None) -> dict[str, Any]:
    """Bundle for swarm_snapshot / Home enrichment."""
    return {
        "subjects": list_subjects(),
        "mission_stack": get_stack(),
        "decisions": list_decisions(limit=50),
        "documents": list_documents(limit=50),
        "thought_stream": list_thoughts(since=since, limit=50),
        "missions": list_missions(),
    }


def legacy_mission_get() -> dict[str, Any]:
    """Shape compatible with existing mission_get consumers."""
    stack = get_stack()
    primary = stack.get("primary")
    if not primary:
        from centurion_cli.mission_sync import read_mission

        return read_mission()
    profile = primary.get("profile") or {}
    if primary.get("why") and not profile.get("whyThisMission"):
        profile = {**profile, "whyThisMission": primary["why"]}
    return {
        "id": primary["id"],
        "statement": primary.get("statement") or primary.get("title") or "",
        "targets": [
            {
                "id": t["id"],
                "title": t["title"],
                "description": t.get("description") or "",
            }
            for t in (primary.get("targets") or [])
        ],
        "profile": profile,
        "path": str(get_centurion_home() / "LIFE_MISSION.md"),
        "exists": True,
        "life": {
            "phase": primary.get("phase"),
            "mission_type": primary.get("mission_type"),
            "situation": primary.get("situation"),
            "why": primary.get("why"),
            "purpose": primary.get("purpose"),
            "subject_id": primary.get("subject_id"),
        },
    }


def legacy_mission_put(fields: dict[str, Any]) -> dict[str, Any]:
    """Accept classic mission_put payload into life.db + markdown."""
    stack = get_stack()
    primary = stack.get("primary")
    mid = str(
        fields.get("id")
        or fields.get("mission_id")
        or (primary or {}).get("id")
        or _new_id()
    )
    payload = {
        "id": mid,
        "title": str(fields.get("statement") or fields.get("title") or "Life Mission")[:80],
        "statement": str(fields.get("statement") or ""),
        "why": str(
            (fields.get("profile") or {}).get("whyThisMission")
            if isinstance(fields.get("profile"), dict)
            else ""
        ),
        "mission_type": "primary",
        "phase": "executing",
        "profile": fields.get("profile") if isinstance(fields.get("profile"), dict) else {},
        "targets": fields.get("targets") if isinstance(fields.get("targets"), list) else [],
    }
    put_mission(payload)
    return legacy_mission_get()
