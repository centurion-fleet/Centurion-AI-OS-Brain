"""Adrian chat service — sanitized context, LLM routing, suggested actions."""

from __future__ import annotations

import logging
import os
import re
import time
from dataclasses import asdict, dataclass, field
from typing import Any

from centurion_cli.adrian.prompts import build_system_prompt

logger = logging.getLogger(__name__)

_SECRET_PATTERNS = (
    re.compile(r"sk-[A-Za-z0-9]{10,}", re.I),
    re.compile(r"api[_-]?key", re.I),
    re.compile(r"password\s*[:=]", re.I),
    re.compile(r"Bearer\s+[A-Za-z0-9._-]+", re.I),
)

_ALLOWED_CONNECTION_STATES = frozenset(
    {
        "disconnected",
        "discovering",
        "connecting",
        "connected",
        "awaiting_approval",
        "error",
    }
)

_ALLOWED_THINKING_HEALTH = frozenset(
    {
        "working_normally",
        "needs_attention",
        "unknown",
        "checking",
    }
)

_RATE_WINDOW_SECONDS = 3600
_RATE_MAX_PER_INSTALL = 40

_rate_buckets: dict[str, list[float]] = {}


@dataclass
class AdrianContext:
    app_version: str = ""
    connection_state: str = "disconnected"
    thinking_health: str = "unknown"
    thinking_message: str = ""
    has_mission: bool = False
    active_target_count: int = 0
    mission_summary: str = ""
    support_code: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class AdrianChatMessage:
    role: str
    content: str

    def to_dict(self) -> dict[str, str]:
        return {"role": self.role, "content": self.content}


@dataclass
class AdrianSuggestedAction:
    id: str
    label: str

    def to_dict(self) -> dict[str, str]:
        return {"id": self.id, "label": self.label}


@dataclass
class AdrianChatRequest:
    install_id: str
    messages: list[AdrianChatMessage]
    context: AdrianContext = field(default_factory=AdrianContext)

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> AdrianChatRequest:
        raw_ctx = payload.get("context") or {}
        context = AdrianContext(
            app_version=_clip(str(raw_ctx.get("app_version") or ""), 32),
            connection_state=_normalize_connection_state(raw_ctx.get("connection_state")),
            thinking_health=_normalize_thinking_health(raw_ctx.get("thinking_health")),
            thinking_message=_clip(_redact_text(str(raw_ctx.get("thinking_message") or "")), 280),
            has_mission=bool(raw_ctx.get("has_mission")),
            active_target_count=max(0, min(int(raw_ctx.get("active_target_count") or 0), 50)),
            mission_summary=_clip(_redact_text(str(raw_ctx.get("mission_summary") or "")), 400),
            support_code=_normalize_support_code(str(raw_ctx.get("support_code") or "")),
        )
        messages: list[AdrianChatMessage] = []
        for item in payload.get("messages") or []:
            if not isinstance(item, dict):
                continue
            role = str(item.get("role") or "").strip().lower()
            if role not in {"user", "assistant"}:
                continue
            content = _clip(_redact_text(str(item.get("content") or "")), 4000)
            if content:
                messages.append(AdrianChatMessage(role=role, content=content))
        install_id = _clip(str(payload.get("install_id") or ""), 64)
        return cls(install_id=install_id, messages=messages[-20:], context=context)


@dataclass
class AdrianChatResponse:
    ok: bool
    reply: str = ""
    suggested_actions: list[AdrianSuggestedAction] = field(default_factory=list)
    message: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "reply": self.reply,
            "suggested_actions": [a.to_dict() for a in self.suggested_actions],
            "message": self.message,
        }


def _clip(text: str, limit: int) -> str:
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _redact_text(text: str) -> str:
    out = text
    for pattern in _SECRET_PATTERNS:
        out = pattern.sub("[redacted]", out)
    return out


def _normalize_connection_state(value: Any) -> str:
    raw = str(value or "disconnected").strip().lower()
    if raw in _ALLOWED_CONNECTION_STATES:
        return raw
    if raw == "awaitingapproval":
        return "awaiting_approval"
    return "disconnected"


def _normalize_thinking_health(value: Any) -> str:
    raw = str(value or "unknown").strip().lower()
    if raw in _ALLOWED_THINKING_HEALTH:
        return raw
    return "unknown"


def _normalize_support_code(code: str) -> str:
    raw = code.strip().upper().replace(" ", "")
    if len(raw) == 6 and "-" not in raw:
        raw = f"{raw[:3]}-{raw[3:]}"
    if re.fullmatch(r"[2-9A-HJ-NP-Z]{3}-[2-9A-HJ-NP-Z]{3}", raw):
        return raw
    return ""


def _check_rate_limit(install_id: str) -> bool:
    if not install_id:
        return False
    now = time.time()
    bucket = _rate_buckets.setdefault(install_id, [])
    cutoff = now - _RATE_WINDOW_SECONDS
    _rate_buckets[install_id] = [t for t in bucket if t >= cutoff]
    if len(_rate_buckets[install_id]) >= _RATE_MAX_PER_INSTALL:
        return False
    _rate_buckets[install_id].append(now)
    return True


def _context_block(context: AdrianContext) -> str:
    lines = [
        f"App version: {context.app_version or 'unknown'}",
        f"Device link: {context.connection_state}",
        f"Thinking service: {context.thinking_health}",
    ]
    if context.thinking_message:
        lines.append(f"Thinking detail: {context.thinking_message}")
    if context.has_mission:
        lines.append("User has a mission configured.")
        if context.active_target_count:
            lines.append(f"Active mission targets: {context.active_target_count}")
        if context.mission_summary:
            lines.append(f"Mission summary: {context.mission_summary}")
    if context.support_code:
        lines.append(f"Support code on hand: {context.support_code}")
    return "\n".join(lines)


def suggest_actions(context: AdrianContext) -> list[AdrianSuggestedAction]:
    actions: list[AdrianSuggestedAction] = []
    if context.connection_state != "connected":
        actions.append(AdrianSuggestedAction(id="open_connect", label="Open Connect"))
    elif context.thinking_health == "needs_attention":
        actions.append(
            AdrianSuggestedAction(id="try_auto_fix", label="Try to Fix Automatically")
        )
        actions.append(AdrianSuggestedAction(id="open_get_help", label="Open Get Help"))
    elif context.connection_state == "connected":
        actions.append(AdrianSuggestedAction(id="open_get_help", label="Open Get Help"))
    if context.has_mission:
        actions.append(AdrianSuggestedAction(id="open_mission", label="Review Your Mission"))
    return actions[:4]


def _fallback_reply(request: AdrianChatRequest) -> str:
    ctx = request.context
    if ctx.connection_state != "connected":
        return (
            "I'm Adrian — Centurion's guide, always here even when your Centurion isn't linked yet.\n\n"
            "Let's get you connected:\n"
            "1. Make sure your iPhone and Centurion computer share the same Wi‑Fi.\n"
            "2. Open Centurion on your computer.\n"
            "3. In this app, open Connect and tap your Centurion.\n"
            "4. Approve the link on your computer if asked.\n\n"
            "While you try that, you can still review your mission in the Home tab — "
            "staying on mission matters even when the link is down."
        )
    if ctx.thinking_health == "needs_attention":
        return (
            "You're linked to your Centurion, but the thinking service needs attention.\n\n"
            "Try this:\n"
            "1. Open Get Help and tap **Try to Fix Automatically**.\n"
            "2. Tap **Check Again**.\n"
            "3. If it's still stuck, tap **Send to Support** for a code to share with us.\n\n"
            "Your private conversations stay on your network — we're just restoring "
            "how your Centurion thinks on the computer."
        )
    return (
        "I'm Adrian, your Centurion support guide. Tell me what's getting in your way "
        "and I'll walk you through it in plain language — so you can get back to your mission."
    )


def _call_openai(messages: list[dict[str, str]]) -> str | None:
    api_key = (
        os.getenv("CENTURION_ADRIAN_OPENAI_API_KEY")
        or os.getenv("CENTURION_HERALD_OPENAI_API_KEY")
        or os.getenv("OPENAI_API_KEY")
    )
    if not api_key:
        return None
    model = os.getenv("CENTURION_ADRIAN_MODEL") or os.getenv("CENTURION_HERALD_MODEL", "gpt-4o-mini")
    try:
        from openai import OpenAI

        client = OpenAI(api_key=api_key)
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=0.4,
            max_tokens=800,
        )
        choice = response.choices[0].message.content if response.choices else None
        return (choice or "").strip() or None
    except Exception:
        logger.exception("Adrian LLM call failed")
        return None


def chat(request: AdrianChatRequest) -> AdrianChatResponse:
    if not request.install_id:
        return AdrianChatResponse(ok=False, message="Missing install identifier.")
    if not _check_rate_limit(request.install_id):
        return AdrianChatResponse(
            ok=False,
            message="You've reached the hourly limit for Adrian. Please try again later.",
        )
    if not request.messages or request.messages[-1].role != "user":
        return AdrianChatResponse(ok=False, message="Send a user message to continue.")

    system = build_system_prompt()
    llm_messages: list[dict[str, str]] = [
        {"role": "system", "content": system},
        {
            "role": "system",
            "content": f"Current sanitized app context:\n{_context_block(request.context)}",
        },
    ]
    for msg in request.messages:
        llm_messages.append(msg.to_dict())

    reply = _call_openai(llm_messages) or _fallback_reply(request)
    actions = suggest_actions(request.context)
    return AdrianChatResponse(ok=True, reply=reply, suggested_actions=actions)
