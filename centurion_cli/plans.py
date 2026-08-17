"""Host-backed Plans store for Sovereign Remote.

Plans are reviewable proposals (not Life Mission). Remote apps sync via
``plans_list`` / ``plan_get`` / ``plan_put`` / ``plan_decide`` /
``plan_share`` / ``plan_comment`` / ``plan_templates_*``.

Storage layout under ``{CENTURION_HOME}/plans/``:
- ``index.json`` — lightweight list metadata
- ``{id}.json`` — full plan document
- ``../plan_templates/{id}.json`` — reusable templates
"""

from __future__ import annotations

import json
import re
import uuid
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from centurion_constants import get_centurion_home

PLAN_STATUSES = (
    "pending_review",
    "proceeded",
    "held",
    "adjusted",
    "completed",
    "rejected",
)
# Aliases accepted on write → canonical status
_STATUS_ALIASES = {
    "proposed": "pending_review",
    "in_progress": "proceeded",
    "paused": "held",
    "active": "proceeded",
}
RISK_LEVELS = ("low", "medium", "high")
DECIDE_CHOICES = ("approve", "reject", "request_changes", "hold")

_HIGH_RISK_RE = re.compile(
    r"\b(rm\s+-rf|sudo|drop\s+table|delete\s+from|credential|password|api[_\s-]?key|"
    r"wire\s*transfer|send\s+money|production\s+deploy|force\s*push)\b",
    re.I,
)
_MEDIUM_RISK_RE = re.compile(
    r"\b(email|send|post|publish|external|network|ssh|deploy|migrate|overwrite|"
    r"delete|remove|write\s+file|patch)\b",
    re.I,
)

_SEED_TEMPLATES: list[dict[str, Any]] = [
    {
        "id": "research-brief",
        "title": "Research & brief",
        "summary": "Gather sources, synthesize findings, deliver a one-page brief for review.",
        "goal": "Produce a clear brief before any external share.",
        "steps": [
            "Clarify the question and success criteria",
            "Gather primary sources and note confidence",
            "Draft a one-page brief with recommendations",
            "Pause for your Proceed before sharing externally",
        ],
        "risks": ["Sources may be incomplete", "External share without review"],
    },
    {
        "id": "safe-change",
        "title": "Safe change checklist",
        "summary": "Plan a careful change with rollback and verification.",
        "goal": "Make a reversible change with a clear verification step.",
        "steps": [
            "Describe the change and blast radius",
            "Prepare a rollback path",
            "Apply the change in the smallest safe scope",
            "Verify outcome and report back",
        ],
        "risks": ["Hard-to-undo change", "Missing verification"],
    },
    {
        "id": "vendor-outreach",
        "title": "Vendor / outreach",
        "summary": "Draft outreach, confirm tone and facts, then send only after Proceed.",
        "goal": "Prepare outreach that waits for your Proceed before sending.",
        "steps": [
            "Confirm recipient and purpose",
            "Draft the message",
            "Fact-check names, numbers, and commitments",
            "Wait for Proceed before any send",
        ],
        "risks": ["Sending before approval", "Incorrect facts"],
    },
    {
        "id": "weekly-ops",
        "title": "Weekly ops review",
        "summary": "Summarize the week, surface decisions, and propose next actions.",
        "goal": "Give a calm weekly picture with clear asks.",
        "steps": [
            "List finished work and open loops",
            "Flag decisions that need your choice",
            "Propose next-week priorities",
            "Wait for Proceed on any new initiative",
        ],
        "risks": ["Starting new work without approval"],
    },
]


def plans_dir() -> Path:
    path = get_centurion_home() / "plans"
    path.mkdir(parents=True, exist_ok=True)
    return path


def templates_dir() -> Path:
    path = get_centurion_home() / "plan_templates"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _index_path() -> Path:
    return plans_dir() / "index.json"


def _plan_path(plan_id: str) -> Path:
    return plans_dir() / f"{plan_id}.json"


def _read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return deepcopy(default)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return deepcopy(default)


def _write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(path)


def _as_str_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        text = value.strip()
        return [text] if text else []
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            if isinstance(item, dict):
                title = str(item.get("title") or item.get("detail") or item.get("text") or "").strip()
                if title:
                    out.append(title)
            else:
                text = str(item).strip()
                if text:
                    out.append(text)
        return out
    return []


def normalize_status(value: Any) -> str:
    raw = str(value or "pending_review").strip().lower()
    raw = _STATUS_ALIASES.get(raw, raw)
    return raw if raw in PLAN_STATUSES else "pending_review"


def classify_risk(steps: list[str], risks: list[str] | None = None, goal: str = "") -> str:
    """Heuristic Low / Medium / High from plan text."""
    blob = " ".join([goal or "", *(steps or []), *(risks or [])])
    if _HIGH_RISK_RE.search(blob):
        return "high"
    if _MEDIUM_RISK_RE.search(blob) or len(steps or []) >= 5:
        return "medium"
    return "low"


def _empty_share() -> dict[str, Any]:
    return {"board_id": None, "reviewers": [], "comments": []}


def _normalize_plan(raw: dict[str, Any], *, plan_id: str | None = None) -> dict[str, Any]:
    pid = str(plan_id or raw.get("id") or uuid.uuid4())
    steps = _as_str_list(raw.get("steps"))
    risks = _as_str_list(raw.get("risks"))
    goal = str(raw.get("goal") or "").strip()
    risk = str(raw.get("risk") or "").strip().lower()
    if risk not in RISK_LEVELS:
        risk = classify_risk(steps, risks, goal)

    share = raw.get("share") if isinstance(raw.get("share"), dict) else {}
    reviewers = share.get("reviewers") if isinstance(share.get("reviewers"), list) else []
    comments = share.get("comments") if isinstance(share.get("comments"), list) else []

    created = str(raw.get("created_at") or raw.get("createdAt") or _now_iso())
    updated = str(raw.get("updated_at") or raw.get("updatedAt") or created)

    return {
        "id": pid,
        "title": str(raw.get("title") or "Untitled plan").strip() or "Untitled plan",
        "summary": str(raw.get("summary") or "").strip(),
        "goal": goal,
        "status": normalize_status(raw.get("status")),
        "risk": risk,
        "steps": steps,
        "risks": risks,
        "open_questions": _as_str_list(
            raw.get("open_questions") or raw.get("openQuestions")
        ),
        "requirements": _as_str_list(raw.get("requirements")),
        "reasoning": str(raw.get("reasoning") or "").strip(),
        "related_mission": (
            str(raw.get("related_mission") or raw.get("relatedMission") or "").strip() or None
        ),
        "signal_id": (
            str(raw.get("signal_id") or raw.get("signalId") or "").strip() or None
        ),
        "source_session_id": (
            str(raw.get("source_session_id") or "").strip() or None
        ),
        "template_id": (str(raw.get("template_id") or "").strip() or None),
        "outcome_summary": (
            str(raw.get("outcome_summary") or "").strip() or None
        ),
        "created_at": created,
        "updated_at": updated,
        "completed_at": (
            str(raw.get("completed_at") or "").strip() or None
        ),
        "share": {
            "board_id": share.get("board_id"),
            "reviewers": reviewers,
            "comments": comments,
        },
    }


def _plan_to_ios(plan: dict[str, Any]) -> dict[str, Any]:
    """Emit both snake_case host fields and camelCase keys iOS already uses."""
    return {
        **plan,
        "openQuestions": plan.get("open_questions") or [],
        "relatedMission": plan.get("related_mission"),
        "signalId": plan.get("signal_id"),
        "createdAt": plan.get("created_at"),
        "updatedAt": plan.get("updated_at"),
        "completedAt": plan.get("completed_at"),
        "templateId": plan.get("template_id"),
        "outcomeSummary": plan.get("outcome_summary"),
    }


def _load_index() -> list[dict[str, Any]]:
    data = _read_json(_index_path(), [])
    return data if isinstance(data, list) else []


def _save_index(entries: list[dict[str, Any]]) -> None:
    _write_json(_index_path(), entries)


def _index_entry(plan: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": plan["id"],
        "title": plan["title"],
        "summary": plan.get("summary") or "",
        "status": plan["status"],
        "risk": plan["risk"],
        "created_at": plan["created_at"],
        "updated_at": plan["updated_at"],
        "template_id": plan.get("template_id"),
    }


def _upsert_index(plan: dict[str, Any]) -> None:
    entries = [e for e in _load_index() if str(e.get("id")) != plan["id"]]
    entries.insert(0, _index_entry(plan))
    entries.sort(key=lambda e: str(e.get("updated_at") or ""), reverse=True)
    _save_index(entries)


def list_plans(status: str | None = None) -> list[dict[str, Any]]:
    """Return full plans, optionally filtered.

    ``status`` filters:
    - ``proposed`` / ``pending_review`` — needs review
    - ``active`` / ``proceeded`` — in progress
    - ``completed`` — done
    - ``all`` / None — everything
    """
    wanted: set[str] | None = None
    key = str(status or "all").strip().lower()
    if key in {"proposed", "pending_review", "pending"}:
        wanted = {"pending_review", "held", "adjusted"}
    elif key in {"active", "proceeded", "in_progress"}:
        wanted = {"proceeded"}
    elif key == "completed":
        wanted = {"completed"}
    elif key in PLAN_STATUSES:
        wanted = {key}
    elif key not in {"all", "*", ""}:
        wanted = {normalize_status(key)}

    out: list[dict[str, Any]] = []
    for entry in _load_index():
        pid = str(entry.get("id") or "")
        if not pid:
            continue
        plan = get_plan(pid)
        if not plan:
            continue
        if wanted is not None and plan["status"] not in wanted:
            continue
        out.append(_plan_to_ios(plan))
    return out


def get_plan(plan_id: str) -> dict[str, Any] | None:
    pid = str(plan_id or "").strip()
    if not pid:
        return None
    path = _plan_path(pid)
    if not path.exists() and pid.lower() != pid:
        path = _plan_path(pid.lower())
    if not path.exists() and pid.upper() != pid:
        path = _plan_path(pid.upper())
    if not path.exists():
        return None
    raw = _read_json(path, None)
    if not isinstance(raw, dict):
        return None
    return _normalize_plan(raw, plan_id=pid)


def put_plan(payload: dict[str, Any] | None) -> dict[str, Any]:
    raw = payload if isinstance(payload, dict) else {}
    existing_id = str(raw.get("id") or "").strip() or None
    existing = get_plan(existing_id) if existing_id else None
    merged = {**(existing or {}), **raw}
    if existing:
        merged["created_at"] = existing["created_at"]
    plan = _normalize_plan(merged, plan_id=existing_id)
    plan["updated_at"] = _now_iso()
    if not existing:
        plan["created_at"] = plan.get("created_at") or plan["updated_at"]
    _write_json(_plan_path(plan["id"]), plan)
    _upsert_index(plan)
    return _plan_to_ios(plan)


def decide_plan(
    plan_id: str,
    choice: str,
    *,
    note: str | None = None,
    reviewer_customer_id: str | None = None,
) -> dict[str, Any]:
    plan = get_plan(plan_id)
    if plan is None:
        raise KeyError(f"plan not found: {plan_id}")

    decision = str(choice or "").strip().lower()
    if decision not in DECIDE_CHOICES:
        raise ValueError(f"invalid choice: {choice}")

    note_text = str(note or "").strip()
    now = _now_iso()
    plan["updated_at"] = now

    if decision == "approve":
        plan["status"] = "proceeded"
        if note_text:
            plan["requirements"] = list(plan.get("requirements") or []) + [note_text]
    elif decision == "reject":
        plan["status"] = "rejected"
        plan["completed_at"] = now
        if note_text:
            plan["outcome_summary"] = note_text
    elif decision == "request_changes":
        plan["status"] = "adjusted"
        if note_text:
            reqs = list(plan.get("requirements") or [])
            reqs.append(note_text)
            plan["requirements"] = reqs
    elif decision == "hold":
        plan["status"] = "held"

    if reviewer_customer_id:
        reviewers = list((plan.get("share") or {}).get("reviewers") or [])
        status_map = {
            "approve": "approved",
            "reject": "rejected",
            "request_changes": "changes_requested",
            "hold": "pending",
        }
        updated = False
        for rev in reviewers:
            if str(rev.get("customer_id")) == str(reviewer_customer_id):
                rev["status"] = status_map[decision]
                rev["note"] = note_text or rev.get("note")
                rev["decided_at"] = now
                updated = True
                break
        if not updated:
            reviewers.append(
                {
                    "customer_id": str(reviewer_customer_id),
                    "role": "observer",
                    "status": status_map[decision],
                    "note": note_text or None,
                    "decided_at": now,
                }
            )
        plan.setdefault("share", _empty_share())
        plan["share"]["reviewers"] = reviewers

    _write_json(_plan_path(plan["id"]), plan)
    _upsert_index(plan)
    return _plan_to_ios(plan)


def complete_plan(plan_id: str, outcome_summary: str | None = None) -> dict[str, Any]:
    plan = get_plan(plan_id)
    if plan is None:
        raise KeyError(f"plan not found: {plan_id}")
    plan["status"] = "completed"
    plan["completed_at"] = _now_iso()
    plan["updated_at"] = plan["completed_at"]
    if outcome_summary:
        plan["outcome_summary"] = str(outcome_summary).strip()
    _write_json(_plan_path(plan["id"]), plan)
    _upsert_index(plan)
    return _plan_to_ios(plan)


def ensure_seed_templates() -> None:
    root = templates_dir()
    for seed in _SEED_TEMPLATES:
        path = root / f"{seed['id']}.json"
        if path.exists():
            continue
        _write_json(
            path,
            {
                **seed,
                "built_in": True,
                "created_at": _now_iso(),
            },
        )


def list_templates() -> list[dict[str, Any]]:
    ensure_seed_templates()
    out: list[dict[str, Any]] = []
    for path in sorted(templates_dir().glob("*.json")):
        raw = _read_json(path, None)
        if isinstance(raw, dict):
            out.append(raw)
    return out


def instantiate_template(template_id: str, overrides: dict[str, Any] | None = None) -> dict[str, Any]:
    ensure_seed_templates()
    path = templates_dir() / f"{template_id}.json"
    if not path.exists():
        # allow lookup by title slug mismatch — scan
        match = None
        for item in list_templates():
            if str(item.get("id")) == str(template_id):
                match = item
                break
        if match is None:
            raise KeyError(f"template not found: {template_id}")
        tmpl = match
    else:
        tmpl = _read_json(path, {})
        if not isinstance(tmpl, dict):
            raise KeyError(f"template not found: {template_id}")

    payload = {
        "title": tmpl.get("title"),
        "summary": tmpl.get("summary"),
        "goal": tmpl.get("goal"),
        "steps": tmpl.get("steps") or [],
        "risks": tmpl.get("risks") or [],
        "open_questions": tmpl.get("open_questions") or [],
        "status": "pending_review",
        "template_id": tmpl.get("id"),
    }
    if isinstance(overrides, dict):
        payload.update({k: v for k, v in overrides.items() if v is not None})
    return put_plan(payload)


def save_plan_as_template(plan_id: str, title: str | None = None) -> dict[str, Any]:
    plan = get_plan(plan_id)
    if plan is None:
        raise KeyError(f"plan not found: {plan_id}")
    slug = re.sub(r"[^a-z0-9]+", "-", (title or plan["title"]).lower()).strip("-") or "custom"
    tmpl_id = f"user-{slug}-{plan['id'][:8]}"
    tmpl = {
        "id": tmpl_id,
        "title": title or plan["title"],
        "summary": plan.get("summary") or "",
        "goal": plan.get("goal") or "",
        "steps": plan.get("steps") or [],
        "risks": plan.get("risks") or [],
        "open_questions": plan.get("open_questions") or [],
        "built_in": False,
        "source_plan_id": plan["id"],
        "created_at": _now_iso(),
    }
    _write_json(templates_dir() / f"{tmpl_id}.json", tmpl)
    return tmpl


def share_plan(
    plan_id: str,
    *,
    reviewer_customer_id: str,
    role: str = "observer",
    board_id: str | None = None,
) -> dict[str, Any]:
    plan = get_plan(plan_id)
    if plan is None:
        raise KeyError(f"plan not found: {plan_id}")

    cid = str(reviewer_customer_id or "").strip()
    if not cid:
        raise ValueError("reviewer_customer_id is required")

    share = plan.get("share") if isinstance(plan.get("share"), dict) else _empty_share()
    reviewers = list(share.get("reviewers") or [])
    for rev in reviewers:
        if str(rev.get("customer_id")) == cid:
            rev["role"] = role or rev.get("role") or "observer"
            rev["status"] = rev.get("status") or "pending"
            break
    else:
        reviewers.append(
            {
                "customer_id": cid,
                "role": role or "observer",
                "status": "pending",
                "shared_at": _now_iso(),
            }
        )

    if board_id:
        share["board_id"] = board_id
    elif not share.get("board_id"):
        # Best-effort: create a local collaboration board for review.
        try:
            from centurion_cli import swarm_state

            board = swarm_state.create_collaboration_board(
                name=f"Plan review: {plan['title'][:48]}",
                objective=plan.get("goal") or plan.get("summary") or plan["title"],
            )
            if isinstance(board, dict) and board.get("ok") is not False:
                share["board_id"] = (
                    board.get("swarm_id")
                    or board.get("id")
                    or board.get("slug")
                    or board.get("board_id")
                )
        except Exception:
            # Sharing metadata still works without a board.
            pass

    share["reviewers"] = reviewers
    plan["share"] = share
    plan["updated_at"] = _now_iso()
    _write_json(_plan_path(plan["id"]), plan)
    _upsert_index(plan)
    return _plan_to_ios(plan)


def comment_plan(
    plan_id: str,
    body: str,
    *,
    author: str = "owner",
) -> dict[str, Any]:
    plan = get_plan(plan_id)
    if plan is None:
        raise KeyError(f"plan not found: {plan_id}")
    text = str(body or "").strip()
    if not text:
        raise ValueError("comment body is required")

    share = plan.get("share") if isinstance(plan.get("share"), dict) else _empty_share()
    comments = list(share.get("comments") or [])
    comments.append(
        {
            "id": str(uuid.uuid4()),
            "author": str(author or "owner"),
            "body": text,
            "at": _now_iso(),
        }
    )
    share["comments"] = comments
    plan["share"] = share
    plan["updated_at"] = _now_iso()
    _write_json(_plan_path(plan["id"]), plan)
    _upsert_index(plan)
    return _plan_to_ios(plan)


def import_legacy_markdown_plans() -> int:
    """Import freeform skill plans from ``.centurion/plans/*.md`` once."""
    legacy = get_centurion_home() / "plans"
    # Host store uses the same directory for JSON; only import .md siblings.
    imported = 0
    for path in sorted(legacy.glob("*.md")):
        marker = plans_dir() / f".imported-{path.stem}"
        if marker.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        title = path.stem
        for line in text.splitlines():
            if line.startswith("# "):
                title = line[2:].strip() or title
                break
        put_plan(
            {
                "title": title,
                "summary": text[:280].strip(),
                "goal": title,
                "steps": [],
                "status": "completed",
                "reasoning": text,
                "outcome_summary": "Imported from legacy markdown plan.",
            }
        )
        marker.write_text(_now_iso(), encoding="utf-8")
        imported += 1
    return imported
