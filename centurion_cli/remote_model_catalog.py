"""Curated direct-API model catalog for Centurion Remote (iPhone).

OpenRouter is intentionally excluded — remote paths must never route through it.
"""

from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from typing import Any

_BLOCKED_PROVIDERS = frozenset({"openrouter", "openrouter/*", "nous", "openai"})


@dataclass(frozen=True)
class RemoteConnector:
    id: str
    display_name: str
    provider: str
    model: str
    category: str  # "text" | "creative"
    key_env: str
    base_url: str = ""
    best_for: str = ""
    creative_kind: str = ""  # image_gen | video_gen | tts

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


_CATALOG: tuple[RemoteConnector, ...] = (
    RemoteConnector(
        id="openai-luna",
        display_name="GPT-5.4 mini",
        provider="openai-api",
        model="gpt-5.4-mini",
        category="text",
        key_env="OPENAI_API_KEY",
        base_url="https://api.openai.com/v1",
        best_for="Quick answers and lightweight tasks",
    ),
    RemoteConnector(
        id="openai-terra",
        display_name="GPT-5.4",
        provider="openai-api",
        model="gpt-5.4",
        category="text",
        key_env="OPENAI_API_KEY",
        base_url="https://api.openai.com/v1",
        best_for="Code, refactoring, and planning",
    ),
    RemoteConnector(
        id="openai-sol-pro",
        display_name="GPT-5.5 Pro",
        provider="openai-api",
        model="gpt-5.5-pro",
        category="text",
        key_env="OPENAI_API_KEY",
        base_url="https://api.openai.com/v1",
        best_for="Deep analysis and long documents",
    ),
    RemoteConnector(
        id="anthropic-sonnet-5",
        display_name="Claude Sonnet 4.6",
        provider="anthropic",
        model="claude-sonnet-4-6",
        category="text",
        key_env="ANTHROPIC_API_KEY",
        base_url="https://api.anthropic.com",
        best_for="Writing, email drafts, and copy",
    ),
    RemoteConnector(
        id="anthropic-opus-4-8",
        display_name="Claude Opus 4.7",
        provider="anthropic",
        model="claude-opus-4-7",
        category="text",
        key_env="ANTHROPIC_API_KEY",
        base_url="https://api.anthropic.com",
        best_for="Legal review, research, and complex reasoning",
    ),
    RemoteConnector(
        id="gemini-3-5-flash",
        display_name="Gemini 3 Flash",
        provider="gemini",
        model="gemini-3-flash-preview",
        category="text",
        key_env="GEMINI_API_KEY",
        base_url="https://generativelanguage.googleapis.com",
        best_for="Fast multimodal reasoning",
    ),
    RemoteConnector(
        id="deepseek-v4-pro",
        display_name="DeepSeek v4 Pro",
        provider="deepseek",
        model="deepseek-v4-pro",
        category="text",
        key_env="DEEPSEEK_API_KEY",
        base_url="https://api.deepseek.com",
        best_for="Cost-effective coding and analysis",
    ),
    RemoteConnector(
        id="xai-grok-4-5",
        display_name="Grok 4.3",
        provider="xai",
        model="grok-4.3",
        category="text",
        key_env="XAI_API_KEY",
        base_url="https://api.x.ai/v1",
        best_for="Real-time knowledge and direct answers",
    ),
    RemoteConnector(
        id="openai-dalle-3",
        display_name="DALL-E 3",
        provider="openai-api",
        model="dall-e-3",
        category="creative",
        key_env="OPENAI_API_KEY",
        base_url="https://api.openai.com/v1",
        best_for="Images, logos, and thumbnails",
        creative_kind="image_gen",
    ),
    RemoteConnector(
        id="runway-gen-4",
        display_name="Runway Gen-4",
        provider="runway",
        model="gen-4",
        category="creative",
        key_env="RUNWAY_API_KEY",
        base_url="https://api.runwayml.com",
        best_for="Video ads and storyboards",
        creative_kind="video_gen",
    ),
    RemoteConnector(
        id="elevenlabs-multilingual",
        display_name="ElevenLabs",
        provider="elevenlabs",
        model="eleven_multilingual_v2",
        category="creative",
        key_env="ELEVENLABS_API_KEY",
        base_url="https://api.elevenlabs.io",
        best_for="Voiceovers and read-aloud",
        creative_kind="tts",
    ),
    RemoteConnector(
        id="fal-kling-v3-4k",
        display_name="Kling",
        provider="fal",
        model="kling-v3-4k",
        category="creative",
        key_env="FAL_KEY",
        base_url="https://fal.ai",
        best_for="High-quality video generation",
        creative_kind="video_gen",
    ),
)

_BY_ID: dict[str, RemoteConnector] = {entry.id: entry for entry in _CATALOG}


def is_openrouter_blocked(provider: str) -> bool:
    """Block OpenRouter / subscription / ambiguous ``openai`` remaps on Remote."""
    lowered = (provider or "").strip().lower()
    if not lowered:
        return False
    if lowered in _BLOCKED_PROVIDERS:
        return True
    return lowered.startswith("openrouter/") or lowered.startswith("nous/")


def get_connector(connector_id: str) -> RemoteConnector | None:
    return _BY_ID.get((connector_id or "").strip())


def iter_catalog() -> tuple[RemoteConnector, ...]:
    return _CATALOG


def _key_configured(key_env: str) -> bool:
    if (os.environ.get(key_env) or "").strip():
        return True
    try:
        from centurion_cli.config import load_env

        return bool((load_env().get(key_env) or "").strip())
    except Exception:
        return False


def build_remote_option_row(
    connector: RemoteConnector,
    *,
    active: bool = False,
    healthy: bool | None = None,
) -> dict[str, Any]:
    configured = _key_configured(connector.key_env)
    row = connector.to_dict()
    row["configured"] = configured
    row["needs_key"] = not configured
    row["active"] = active
    if healthy is not None:
        row["healthy"] = healthy
    return row
