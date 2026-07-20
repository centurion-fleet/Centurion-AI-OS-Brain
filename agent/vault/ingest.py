"""Deliberate Vault ingestion filters — never indiscriminate."""

from __future__ import annotations

import re
from typing import Optional

from tools.threat_patterns import first_threat_message

from agent.vault.types import MemoryType

DEFAULT_MAX_ENTRY_CHARS = 4000

_SECRET_PATTERNS = [
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),
    re.compile(r"\b(?:api[_-]?key|secret[_-]?key|access[_-]?token)\s*[:=]\s*\S+", re.I),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
]

_TRANSCRIPT_HINTS = [
    re.compile(r"(?m)^User:\s"),
    re.compile(r"(?m)^Assistant:\s"),
    re.compile(r"(?m)^Human:\s"),
]


def validate_proposal(
    *,
    text: str,
    memory_type: str,
    max_chars: int = DEFAULT_MAX_ENTRY_CHARS,
    unlocked: bool = True,
    writes_allowed: bool = True,
) -> Optional[str]:
    """Return an error string if the proposal must be rejected, else None."""
    if not writes_allowed:
        return "Vault writes are disabled in this agent context (skip_memory)."
    if not unlocked:
        return "Vault is locked. Unlock before proposing."
    if not text or not text.strip():
        return "Empty memory text."
    stripped = text.strip()
    if len(stripped) > max_chars:
        return f"Entry exceeds max_entry_chars ({len(stripped)} > {max_chars})."
    try:
        MemoryType.parse(memory_type)
    except ValueError as exc:
        return str(exc)

    threat = first_threat_message(stripped, scope="strict")
    if threat:
        return f"Blocked by threat scan: {threat}"

    for pat in _SECRET_PATTERNS:
        if pat.search(stripped):
            return "Looks like a secret or credential — refuse to store in Vault."

    if _looks_like_transcript_dump(stripped):
        return (
            "Looks like a bulk transcript dump. Vault requires deliberate "
            "curated facts, not full conversation logs. Use session_search instead."
        )
    return None


def _looks_like_transcript_dump(text: str) -> bool:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) >= 12:
        hits = sum(1 for pat in _TRANSCRIPT_HINTS if pat.search(text))
        if hits >= 2:
            return True
    # Many alternating role labels
    role_lines = sum(
        1
        for ln in lines
        if ln.startswith("User:") or ln.startswith("Assistant:") or ln.startswith("Human:")
    )
    return role_lines >= 6
