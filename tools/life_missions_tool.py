"""Local Life Missions tools — Subjects → Missions → Targets on the Brain.

Calls ``centurion_cli.life_missions`` (offline SQLite). Not portal Mission Control.
"""

from __future__ import annotations

import json
from typing import Any

from tools.registry import registry, tool_error


def _ok(**payload: Any) -> str:
    return json.dumps({"success": True, **payload}, default=str)


def life_missions_tool(
    action: str,
    mission_id: str = "",
    subject_id: str = "",
    dream_id: str = "",
    target_id: str = "",
    query: str = "",
    title: str = "",
    statement: str = "",
    summary: str = "",
    fields_json: str = "",
    task_id: str | None = None,
) -> str:
    del task_id  # unused — agent loop injects
    try:
        from centurion_cli import life_missions as life
    except Exception as exc:
        return tool_error(f"life_missions unavailable: {exc}")

    action = (action or "").strip().lower()
    try:
        fields: dict[str, Any] = {}
        if fields_json.strip():
            parsed = json.loads(fields_json)
            if isinstance(parsed, dict):
                fields = parsed

        if action in ("stack", "get_stack"):
            return _ok(stack=life.get_stack())
        if action in ("list_missions", "missions"):
            return _ok(missions=life.list_missions())
        if action in ("get_mission", "mission"):
            if not mission_id:
                return tool_error("mission_id required")
            mission = life.get_mission(mission_id)
            if mission is None:
                return tool_error("Mission not found")
            return _ok(mission=mission)
        if action in ("put_mission", "save_mission", "create_mission", "create"):
            payload = dict(fields)
            if mission_id:
                payload.setdefault("id", mission_id)
            if title:
                payload.setdefault("title", title)
            if statement:
                payload.setdefault("statement", statement)
            if subject_id:
                payload.setdefault("subject_id", subject_id)
            # Default new missions to supporting so Chat can add a second
            # mission without demoting the primary unless fields_json says so.
            if "mission_type" not in payload and not mission_id:
                payload.setdefault("mission_type", "supporting")
            return _ok(mission=life.put_mission(payload))
        if action in ("list_subjects", "subjects"):
            return _ok(subjects=life.list_subjects())
        if action in ("put_subject", "save_subject"):
            payload = dict(fields)
            if subject_id:
                payload.setdefault("id", subject_id)
            if title:
                payload.setdefault("name", title)
            return _ok(subject=life.put_subject(payload))
        if action in ("list_dreams", "dreams"):
            return _ok(dreams=life.list_dreams())
        if action in ("put_dream", "save_dream"):
            payload = dict(fields)
            if dream_id:
                payload.setdefault("id", dream_id)
            if title:
                payload.setdefault("title", title)
            return _ok(dream=life.put_dream(payload))
        if action in ("promote_dream",):
            if not dream_id:
                return tool_error("dream_id required")
            return _ok(**life.promote_dream(dream_id, subject_id=subject_id or None))
        if action in ("set_primary",):
            return _ok(stack=life.set_primary(mission_id or None))
        if action in ("put_target", "save_target"):
            payload = dict(fields)
            if mission_id:
                payload.setdefault("mission_id", mission_id)
            if target_id:
                payload.setdefault("id", target_id)
            if title:
                payload.setdefault("title", title)
            return _ok(target=life.put_target(payload))
        if action in ("set_focus", "focus"):
            if not mission_id:
                return tool_error("mission_id required")
            return _ok(state=life.set_focus_target(mission_id, target_id or None))
        if action in ("resolve", "resolve_context"):
            return _ok(matches=life.resolve_context(query or title or statement))
        if action in ("inject", "inject_context"):
            view = {
                "mission_id": mission_id or None,
                "target_id": target_id or None,
                "subject_id": subject_id or None,
            }
            return _ok(**life.inject_context(query or statement or title, current_view=view))
        if action in ("post_thought", "thought"):
            payload = dict(fields)
            if mission_id:
                payload.setdefault("mission_id", mission_id)
            if target_id:
                payload.setdefault("target_id", target_id)
            if summary:
                payload.setdefault("summary", summary)
            return _ok(thought=life.post_thought(payload))
        if action in ("list_thoughts", "thoughts"):
            return _ok(thoughts=life.list_thoughts(limit=50))
        if action in ("log_decision", "decision"):
            payload = dict(fields)
            if mission_id:
                payload.setdefault("mission_id", mission_id)
            if target_id:
                payload.setdefault("target_id", target_id)
            if title:
                payload.setdefault("title", title)
            return _ok(decision=life.log_decision(payload))
        if action in ("list_decisions", "decisions"):
            return _ok(
                decisions=life.list_decisions(
                    mission_id=mission_id or None,
                    limit=50,
                )
            )
        if action in ("list_documents", "documents"):
            return _ok(
                documents=life.list_documents(
                    mission_id=mission_id or None,
                    limit=50,
                )
            )
        if action in ("get_document", "document"):
            doc_id = str(
                fields.get("document_id") or fields.get("id") or query or ""
            ).strip()
            if not doc_id:
                return tool_error("document id required (fields_json.id or query)")
            doc = life.get_document(doc_id)
            if doc is None:
                return tool_error("Document not found")
            return _ok(document=doc)
        if action in ("put_document", "save_document", "life_document_put"):
            payload = dict(fields)
            if mission_id:
                payload.setdefault("mission_id", mission_id)
            if target_id:
                payload.setdefault("target_id", target_id)
            if title:
                payload.setdefault("title", title)
            if summary:
                payload.setdefault("summary", summary)
            if statement and not payload.get("body_md") and not payload.get("body"):
                payload.setdefault("body_md", statement)
            return _ok(document=life.put_document(payload))
        if action in ("snapshot",):
            return _ok(snapshot=life.snapshot_extras())
        return tool_error(
            "Unknown action. Use stack, missions, get_mission, put_mission|create_mission, "
            "subjects, dreams, promote_dream, set_primary, put_target, set_focus, resolve, "
            "inject, thought, thoughts, decision, decisions, list_documents, get_document, "
            "put_document, snapshot."
        )
    except Exception as exc:
        return tool_error(str(exc))


registry.register(
    name="life_missions",
    toolset="life",
    schema={
        "name": "life_missions",
        "description": (
            "Create/update/list Life Missions on this Brain (offline life.db). "
            "Use create_mission or put_mission with fields_json for "
            "mission_type primary|supporting, targets, situation, why. "
            "For finished write-ups bound to a mission (research, analysis, "
            "content, report), use put_document with mission_id — not "
            "upload_document. Prefer plans/plan-artifact when the user must "
            "Approve/Proceed; after accept, optionally put_document with "
            "plan_id and doc_type plan so it appears under the mission. "
            "Also: stack, dreams, focus, thoughts, decisions, documents. "
            "Not portal SaaS."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "description": (
                        "stack|missions|get_mission|put_mission|create_mission|"
                        "subjects|dreams|promote_dream|set_primary|put_target|"
                        "set_focus|resolve|inject|thought|thoughts|decision|"
                        "decisions|list_documents|get_document|put_document|snapshot"
                    ),
                },
                "mission_id": {"type": "string"},
                "subject_id": {"type": "string"},
                "dream_id": {"type": "string"},
                "target_id": {"type": "string"},
                "query": {"type": "string"},
                "title": {"type": "string"},
                "statement": {"type": "string"},
                "summary": {"type": "string"},
                "fields_json": {
                    "type": "string",
                    "description": (
                        "JSON for put/create. Mission example: "
                        '{"title":"Cashflow","statement":"...","mission_type":"supporting"}. '
                        "Document example: "
                        '{"mission_id":"...","title":"...","doc_type":"research|analysis|'
                        'content|report|plan|other","summary":"...","body_md":"...",'
                        '"plan_id":null,"source":"agent"}'
                    ),
                },
            },
            "required": ["action"],
        },
    },
    handler=lambda args, **kw: life_missions_tool(
        action=str(args.get("action") or ""),
        mission_id=str(args.get("mission_id") or ""),
        subject_id=str(args.get("subject_id") or ""),
        dream_id=str(args.get("dream_id") or ""),
        target_id=str(args.get("target_id") or ""),
        query=str(args.get("query") or ""),
        title=str(args.get("title") or ""),
        statement=str(args.get("statement") or ""),
        summary=str(args.get("summary") or ""),
        fields_json=str(args.get("fields_json") or ""),
        task_id=kw.get("task_id"),
    ),
)

registry.register(
    name="subject_resolver",
    toolset="life",
    schema={
        "name": "subject_resolver",
        "description": "Match a query to Subject / Mission / Target on this Brain.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Natural language to resolve."},
            },
            "required": ["query"],
        },
    },
    handler=lambda args, **kw: life_missions_tool(
        action="resolve",
        query=str(args.get("query") or ""),
        task_id=kw.get("task_id"),
    ),
)

registry.register(
    name="thought_stream",
    toolset="life",
    schema={
        "name": "thought_stream",
        "description": "Post or list thought-stream entries for Life Missions.",
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "description": "list (default) or post",
                },
                "summary": {"type": "string"},
                "mission_id": {"type": "string"},
                "target_id": {"type": "string"},
                "detail": {"type": "string"},
            },
        },
    },
    handler=lambda args, **kw: life_missions_tool(
        action="thought"
        if str(args.get("action") or "").lower() == "post"
        else "thoughts",
        summary=str(args.get("summary") or ""),
        mission_id=str(args.get("mission_id") or ""),
        target_id=str(args.get("target_id") or ""),
        fields_json=(
            json.dumps({"detail": str(args.get("detail") or "")})
            if args.get("detail")
            else ""
        ),
        task_id=kw.get("task_id"),
    ),
)
