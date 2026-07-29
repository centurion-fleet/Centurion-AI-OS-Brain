"""Legacy portal Mission Control tool — quarantined from Brain product.

Life Missions live in offline ``life.db`` via ``life_missions``. This tool
remains registered only so old schemas do not crash discovery; every action
returns a clear offline redirect.
"""

from __future__ import annotations

from tools.registry import registry, tool_error

_OFFLINE_MSG = (
    "Mission Control (portal / ctk_proj token) is frozen on this Brain. "
    "Life Missions are local: use the life_missions tool (life.db). "
    "Reviewable Plans: use the plans tool. Never ask the user for a portal token."
)

MC_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "action": {
            "type": "string",
            "enum": ["sync", "complete_task", "upload_document", "invite_friend"],
            "description": "Ignored — portal Mission Control is unavailable.",
        },
        "task_id": {"type": "string"},
        "result": {"type": "string"},
        "path": {"type": "string"},
        "storage_path": {"type": "string"},
        "title": {"type": "string"},
        "published_to_program": {"type": "boolean"},
        "invited_customer_id": {"type": "string"},
        "since": {"type": "string"},
    },
    "required": ["action"],
}


async def handle_mission_control(args: dict, **kwargs) -> str:
    del args, kwargs
    return tool_error(_OFFLINE_MSG)


registry.register(
    name="mission_control",
    toolset="centurion-mission-control",
    schema=MC_SCHEMA,
    handler=handle_mission_control,
    emoji="🎯",
    description=(
        "DEPRECATED — portal Mission Control is frozen. "
        "Use life_missions for Life Missions and plans for reviewable Plans. "
        "Never ask for ctk_proj / portal tokens."
    ),
)
