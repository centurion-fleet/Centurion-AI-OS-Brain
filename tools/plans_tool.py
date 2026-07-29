"""Local Plans tools — reviewable proposals under ``{CENTURION_HOME}/plans/``.

Offline only. Not portal Mission Control. Not Life Missions (use life_missions).
"""

from __future__ import annotations

import json
from typing import Any

from tools.registry import registry, tool_error


def _ok(**payload: Any) -> str:
    return json.dumps({"success": True, **payload}, default=str)


def plans_tool(
    action: str,
    plan_id: str = "",
    title: str = "",
    goal: str = "",
    fields_json: str = "",
    choice: str = "",
    note: str = "",
    status: str = "",
    outcome_summary: str = "",
    task_id: str | None = None,
) -> str:
    del task_id
    try:
        from centurion_cli import plans as plans_mod
    except Exception as exc:
        return tool_error(f"plans unavailable: {exc}")

    action = (action or "").strip().lower()
    try:
        fields: dict[str, Any] = {}
        if fields_json.strip():
            parsed = json.loads(fields_json)
            if isinstance(parsed, dict):
                fields = parsed

        if action in ("list", "list_plans"):
            return _ok(plans=plans_mod.list_plans(status or None))
        if action in ("get", "get_plan"):
            if not plan_id:
                return tool_error("plan_id required")
            plan = plans_mod.get_plan(plan_id)
            if plan is None:
                return tool_error("Plan not found")
            return _ok(plan=plan)
        if action in ("put", "put_plan", "save", "create", "create_plan"):
            payload = dict(fields)
            if plan_id:
                payload.setdefault("id", plan_id)
            if title:
                payload.setdefault("title", title)
            if goal:
                payload.setdefault("goal", goal)
            return _ok(plan=plans_mod.put_plan(payload))
        if action in ("decide", "decide_plan"):
            if not plan_id:
                return tool_error("plan_id required")
            if not choice:
                return tool_error("choice required (approve|reject|request_changes|hold)")
            return _ok(
                plan=plans_mod.decide_plan(plan_id, choice, note=note or None)
            )
        if action in ("complete", "complete_plan"):
            if not plan_id:
                return tool_error("plan_id required")
            return _ok(
                plan=plans_mod.complete_plan(
                    plan_id, outcome_summary=outcome_summary or None
                )
            )
        if action in ("templates", "list_templates"):
            return _ok(templates=plans_mod.list_templates())
        if action in ("instantiate", "from_template"):
            tid = str(fields.get("template_id") or plan_id or "").strip()
            if not tid:
                return tool_error("template_id required (plan_id or fields_json)")
            return _ok(plan=plans_mod.instantiate_template(tid, overrides=fields or None))
        return tool_error(
            "Unknown action. Use list, get, put|create, decide, complete, "
            "templates, instantiate."
        )
    except KeyError as exc:
        return tool_error(str(exc))
    except ValueError as exc:
        return tool_error(str(exc))
    except Exception as exc:
        return tool_error(str(exc))


registry.register(
    name="plans",
    toolset="plans",
    schema={
        "name": "plans",
        "description": (
            "Create/list/update reviewable Plans on this Brain (local plans/). "
            "Use put/create with fields_json for title, goal, steps, risks. "
            "decide: approve|reject|request_changes|hold. Not Life Missions "
            "(use life_missions). Not portal Mission Control."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "description": (
                        "list|get|put|create|decide|complete|templates|instantiate"
                    ),
                },
                "plan_id": {"type": "string"},
                "title": {"type": "string"},
                "goal": {"type": "string"},
                "choice": {
                    "type": "string",
                    "description": "For decide: approve|reject|request_changes|hold",
                },
                "note": {"type": "string"},
                "status": {
                    "type": "string",
                    "description": "For list filter: proposed|active|completed|all",
                },
                "outcome_summary": {"type": "string"},
                "fields_json": {
                    "type": "string",
                    "description": (
                        'JSON for put/create. Example: '
                        '{"title":"Cashflow plan","goal":"...","steps":["A","B"],'
                        '"risks":["..."]}'
                    ),
                },
            },
            "required": ["action"],
        },
    },
    handler=lambda args, **kw: plans_tool(
        action=str(args.get("action") or ""),
        plan_id=str(args.get("plan_id") or ""),
        title=str(args.get("title") or ""),
        goal=str(args.get("goal") or ""),
        fields_json=str(args.get("fields_json") or ""),
        choice=str(args.get("choice") or ""),
        note=str(args.get("note") or ""),
        status=str(args.get("status") or ""),
        outcome_summary=str(args.get("outcome_summary") or ""),
        task_id=kw.get("task_id"),
    ),
)
