"""Vault tool — deliberate offline long-term memory for the agent loop.

Actions: status, propose, commit, reject, search, get, proposals
Requires Vault unlock. Never auto-ingests turns.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Optional

from tools.registry import registry

logger = logging.getLogger(__name__)

VAULT_SCHEMA = {
    "name": "vault",
    "description": (
        "Offline sealed long-term memory (Vault). Use deliberately — never dump "
        "full transcripts. Types: core (stable facts/preferences), experiential "
        "(significant events/decisions), pattern (recurring workflows). "
        "Propose then commit. Search with hybrid keyword+semantic recall. "
        "Vault must be unlocked (centurion vault unlock). "
        "Keep MEMORY.md for tiny hot-cache facts; use Vault for long-horizon memory."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": [
                    "status",
                    "propose",
                    "commit",
                    "reject",
                    "search",
                    "get",
                    "proposals",
                ],
                "description": "Vault action to perform.",
            },
            "memory_type": {
                "type": "string",
                "enum": ["core", "experiential", "pattern"],
                "description": "Required for propose. Optional filter for search.",
            },
            "text": {
                "type": "string",
                "description": "Memory text for propose.",
            },
            "rationale": {
                "type": "string",
                "description": "Why this belongs in Vault (propose).",
            },
            "tags": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Optional tags for propose.",
            },
            "importance": {
                "type": "integer",
                "description": "1-10 importance (default 5).",
            },
            "proposal_id": {
                "type": "string",
                "description": "Proposal id for commit/reject.",
            },
            "entry_id": {
                "type": "string",
                "description": "Entry id for get.",
            },
            "query": {
                "type": "string",
                "description": "Search query.",
            },
            "limit": {
                "type": "integer",
                "description": "Max search results (default 8).",
            },
        },
        "required": ["action"],
    },
}


def check_vault_requirements() -> bool:
    """Vault tool is always registered; runtime checks lock/init."""
    return True


def _get_vault(*, writes_allowed: bool = True):
    from agent.vault import open_vault

    return open_vault(writes_allowed=writes_allowed)


def vault_tool(
    action: str,
    memory_type: str = "",
    text: str = "",
    rationale: str = "",
    tags: Optional[list] = None,
    importance: int = 5,
    proposal_id: str = "",
    entry_id: str = "",
    query: str = "",
    limit: int = 8,
    writes_allowed: bool = True,
    source_session: Optional[str] = None,
    **_kwargs: Any,
) -> str:
    """Dispatch Vault actions; always returns a JSON string."""
    try:
        vault = _get_vault(writes_allowed=writes_allowed)
    except Exception as exc:
        return json.dumps({"success": False, "error": str(exc)})

    action = (action or "").strip().lower()
    try:
        if action == "status":
            return json.dumps({"success": True, "status": vault.status()})

        if action == "propose":
            prop = vault.propose(
                memory_type=memory_type,
                text=text,
                rationale=rationale,
                tags=tags or [],
                importance=importance,
                source_session=source_session,
            )
            return json.dumps(
                {
                    "success": True,
                    "proposal": prop.to_public_dict(),
                    "next": "Call vault(action='commit', proposal_id=...) to seal it.",
                }
            )

        if action == "commit":
            if not proposal_id:
                return json.dumps({"success": False, "error": "proposal_id required"})
            entry = vault.commit(proposal_id)
            return json.dumps({"success": True, "entry": entry.to_public_dict()})

        if action == "reject":
            if not proposal_id:
                return json.dumps({"success": False, "error": "proposal_id required"})
            prop = vault.reject(proposal_id)
            return json.dumps({"success": True, "proposal": prop.to_public_dict()})

        if action == "search":
            if not query:
                return json.dumps({"success": False, "error": "query required"})
            hits = vault.search(
                query,
                memory_type=memory_type or None,
                limit=limit or 8,
            )
            return json.dumps(
                {
                    "success": True,
                    "results": [h.to_public_dict() for h in hits],
                    "count": len(hits),
                }
            )

        if action == "get":
            if not entry_id:
                return json.dumps({"success": False, "error": "entry_id required"})
            entry = vault.get(entry_id)
            if not entry:
                return json.dumps({"success": False, "error": "Entry not found"})
            return json.dumps({"success": True, "entry": entry.to_public_dict()})

        if action == "proposals":
            props = vault.list_proposals(status="pending")
            return json.dumps(
                {
                    "success": True,
                    "proposals": [p.to_public_dict() for p in props],
                    "count": len(props),
                }
            )

        return json.dumps(
            {
                "success": False,
                "error": f"Unknown action {action!r}. "
                "Use status|propose|commit|reject|search|get|proposals.",
            }
        )
    except Exception as exc:
        return json.dumps({"success": False, "error": str(exc)})


registry.register(
    name="vault",
    toolset="vault",
    schema=VAULT_SCHEMA,
    handler=lambda args, **kw: vault_tool(
        action=args.get("action", ""),
        memory_type=args.get("memory_type", ""),
        text=args.get("text", ""),
        rationale=args.get("rationale", ""),
        tags=args.get("tags"),
        importance=args.get("importance", 5),
        proposal_id=args.get("proposal_id", ""),
        entry_id=args.get("entry_id", ""),
        query=args.get("query", ""),
        limit=args.get("limit", 8),
        writes_allowed=kw.get("writes_allowed", True),
        source_session=kw.get("session_id"),
    ),
    check_fn=check_vault_requirements,
)
