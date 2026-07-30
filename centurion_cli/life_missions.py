"""Offline Life Missions store — Subjects → Missions → Targets on the Brain.

Canonical path: ``{get_centurion_home()}/life/life.db``.
Projects LIFE_MISSION.md via ``mission_sync`` so the agent prompt stays stable.
No portal / Supabase — Remote and GTK talk to this module only.
"""

from __future__ import annotations

import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from centurion_constants import get_centurion_home

_SCHEMA_VERSION = 2

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


def ensure_schema(conn: sqlite3.Connection | None = None) -> None:
    own = conn is None
    if own:
        path = life_db_path()
        conn = sqlite3.connect(str(path))
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
    if own:
        conn.commit()
        conn.close()


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
    bootstrap_from_markdown_if_empty()
    with _conn() as conn:
        rows = conn.execute(
            "SELECT * FROM life_subjects ORDER BY sort_order, name"
        ).fetchall()
        return [_row_dict(r) for r in rows]  # type: ignore[misc]


def put_subject(fields: dict[str, Any]) -> dict[str, Any]:
    bootstrap_from_markdown_if_empty()
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
    bootstrap_from_markdown_if_empty()
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
    bootstrap_from_markdown_if_empty()
    with _conn() as conn:
        rows = conn.execute(
            "SELECT * FROM life_missions ORDER BY stack_sort_order, created_at"
        ).fetchall()
        return [_mission_dict(conn, r) for r in rows]


def get_mission(mission_id: str) -> dict[str, Any] | None:
    bootstrap_from_markdown_if_empty()
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM life_missions WHERE id = ?", (mission_id,)
        ).fetchone()
        if not row:
            return None
        return _mission_dict(conn, row)


def put_mission(fields: dict[str, Any]) -> dict[str, Any]:
    bootstrap_from_markdown_if_empty()
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
    bootstrap_from_markdown_if_empty()
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
            if m["id"] != (primary or {}).get("id") and m.get("mission_type") != "dream"
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
        raise ValueError("mission_id required")
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


def document_excerpt(doc: dict[str, Any], *, max_chars: int = 400) -> str:
    body = str(doc.get("body_md") or "").strip()
    summary = str(doc.get("summary") or "").strip()
    text = body or summary
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1].rstrip() + "…"


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
                "SELECT id, title, summary, doc_type FROM life_documents "
                "WHERE mission_id = ?",
                (mission["id"],),
            ).fetchall()
            for doc in docs:
                hay = " ".join(
                    [doc["title"] or "", doc["summary"] or "", doc["doc_type"] or ""]
                ).lower()
                for term in terms:
                    if term in hay:
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
                                },
                                "confidence": 0.78,
                                "matched_field": "document.title"
                                if term in (doc["title"] or "").lower()
                                else "document",
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
    bootstrap_from_markdown_if_empty()
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
    bootstrap_from_markdown_if_empty()
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
    bootstrap_from_markdown_if_empty()
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
