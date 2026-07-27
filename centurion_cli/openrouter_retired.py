"""OpenRouter is retired from Centurion.

It must not appear in doctor/status/setup pickers, must not be loaded as a
model-provider plugin, and must not be used for inference or auxiliary calls.
Existing ``OPENROUTER_API_KEY`` / ``model.provider: openrouter`` configs are
ignored; users should switch to a direct BYOK provider.
"""

from __future__ import annotations

import os
from typing import Optional

from utils import base_url_host_matches

# Canonical ids / aliases that must never resolve to the aggregator.
RETIRED_PROVIDER_IDS = frozenset({
    "openrouter",
    "openrouter/*",
})

RETIRED_ENV_VARS = frozenset({
    "OPENROUTER_API_KEY",
    "OPENROUTER_BASE_URL",
})


def enforce_openrouter_disabled() -> None:
    """Process-wide kill switch — safe to call repeatedly."""
    os.environ["CENTURION_DISABLE_OPENROUTER"] = "1"


def is_openrouter_provider(provider: Optional[str]) -> bool:
    lowered = (provider or "").strip().lower()
    if not lowered:
        return False
    if lowered in RETIRED_PROVIDER_IDS:
        return True
    return lowered.startswith("openrouter/")


def is_openrouter_base_url(url: Optional[str]) -> bool:
    return bool(url) and base_url_host_matches(str(url), "openrouter.ai")


def is_openrouter_blocked(provider: Optional[str] = None, base_url: Optional[str] = None) -> bool:
    """True when a provider id or base URL targets the retired aggregator."""
    return is_openrouter_provider(provider) or is_openrouter_base_url(base_url)


def retired_provider_message(*, remote: bool = False) -> str:
    """User-facing copy that does not name the retired aggregator."""
    where = "Centurion Remote" if remote else "Centurion"
    return (
        f"That thinking service is no longer available in {where}. "
        "Choose a direct API provider (Anthropic, OpenAI, DeepSeek, Gemini, …) "
        "and set its key in ~/.centurion/.env, or run: centurion setup"
    )
