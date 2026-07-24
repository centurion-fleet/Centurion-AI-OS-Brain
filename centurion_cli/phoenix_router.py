"""Keyword router for Centurion Remote Phoenix auto-routing mode."""

from __future__ import annotations

import re
from typing import Pattern

from centurion_cli.remote_model_catalog import get_connector

_RULES: list[tuple[Pattern[str], str]] = [
    (re.compile(r"\b(write email|draft email|copy|newsletter)\b", re.I), "anthropic-sonnet-5"),
    (re.compile(r"\b(analyze contract|legal|long document|research)\b", re.I), "anthropic-opus-4-8"),
    (re.compile(r"\b(generate video|30-?second ad|storyboard)\b", re.I), "runway-gen-4"),
    (re.compile(r"\b(voiceover|clone voice|read aloud)\b", re.I), "elevenlabs-multilingual"),
    (re.compile(r"\b(generate image|logo|thumbnail)\b", re.I), "openai-dalle-3"),
    (re.compile(r"\b(quick|short answer|what is)\b", re.I), "openai-luna"),
    (re.compile(r"\b(code|refactor|debug|plan)\b", re.I), "openai-terra"),
]


def resolve(user_message: str, *, categories: set[str] | None = None) -> str | None:
    """Return a catalog connector id for *user_message*, or None to keep manual selection.

    When *categories* is set (e.g. ``{"text"}`` for Crypto Chat), creative
    connectors are skipped so chat routing never switches to image/video/tts.
    """
    text = (user_message or "").strip()
    if not text:
        return None
    for pattern, connector_id in _RULES:
        if pattern.search(text):
            connector = get_connector(connector_id)
            if connector is None:
                continue
            if categories is not None and connector.category not in categories:
                continue
            return connector_id
    return None


def describe_route(connector_id: str) -> str:
    connector = get_connector(connector_id)
    if connector is None:
        return ""
    return connector.display_name
