"""Helpers for reading the effective fallback provider chain from config."""

from __future__ import annotations

from typing import Any


def _normalized_base_url(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip().rstrip("/")


def _iter_fallback_entries(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, dict):
        candidates = [raw]
    elif isinstance(raw, list):
        candidates = raw
    else:
        return []

    entries: list[dict[str, Any]] = []
    for entry in candidates:
        if not isinstance(entry, dict):
            continue
        provider = str(entry.get("provider") or "").strip()
        model = str(entry.get("model") or "").strip()
        if not provider or not model:
            continue

        normalized = dict(entry)
        normalized["provider"] = provider
        normalized["model"] = model

        base_url = _normalized_base_url(entry.get("base_url"))
        if base_url:
            normalized["base_url"] = base_url

        entries.append(normalized)
    return entries


def _entry_identity(entry: dict[str, Any]) -> tuple[str, str, str]:
    return (
        str(entry.get("provider") or "").strip().lower(),
        str(entry.get("model") or "").strip().lower(),
        _normalized_base_url(entry.get("base_url")).lower(),
    )


def get_fallback_chain(config: dict[str, Any] | None) -> list[dict[str, Any]]:
    """Return the effective fallback chain merged across old and new config keys.

    ``fallback_providers`` remains the primary source of truth and keeps its
    order. Legacy ``fallback_model`` entries are appended afterwards unless
    they target the same provider/model/base_url route as an earlier entry.
    The returned list always contains fresh dict copies.
    """

    config = config or {}
    chain: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()

    for key in ("fallback_providers", "fallback_model"):
        for entry in _iter_fallback_entries(config.get(key)):
            identity = _entry_identity(entry)
            if identity in seen:
                continue
            seen.add(identity)
            chain.append(entry)

    return chain


def set_fallback_chain(config: dict[str, Any], chain: list[dict[str, Any]]) -> None:
    """Persist ``fallback_providers`` and drop the legacy ``fallback_model`` key.

    Mutates ``config`` in place. Caller is responsible for ``save_config``.
    """
    cleaned: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for entry in _iter_fallback_entries(chain):
        identity = _entry_identity(entry)
        if identity in seen:
            continue
        seen.add(identity)
        cleaned.append(dict(entry))
    config["fallback_providers"] = cleaned
    config.pop("fallback_model", None)


def upsert_fallback_entry(
    config: dict[str, Any],
    entry: dict[str, Any],
    *,
    slot: int | None = None,
) -> list[dict[str, Any]]:
    """Insert or replace a fallback entry.

    ``slot`` is 1-based (Backup #1 / #2). When ``None``, append if not already
    present. Returns the updated chain (also written into ``config``).
    """
    chain = get_fallback_chain(config)
    normalized_list = _iter_fallback_entries([entry])
    if not normalized_list:
        raise ValueError("Fallback entry requires provider and model.")
    new_entry = dict(normalized_list[0])
    new_id = _entry_identity(new_entry)

    if slot is not None:
        if slot < 1:
            raise ValueError("Backup slot must be 1 or greater.")
        index = slot - 1
        # Drop any existing duplicate of this route first.
        chain = [e for e in chain if _entry_identity(e) != new_id]
        if index >= len(chain):
            chain.append(new_entry)
        else:
            chain[index] = new_entry
    else:
        for existing in chain:
            if _entry_identity(existing) == new_id:
                set_fallback_chain(config, chain)
                return get_fallback_chain(config)
        chain.append(new_entry)

    set_fallback_chain(config, chain)
    return get_fallback_chain(config)


def remove_fallback_slot(config: dict[str, Any], slot: int) -> list[dict[str, Any]]:
    """Remove the 1-based backup slot from the chain. Returns the updated chain."""
    if slot < 1:
        raise ValueError("Backup slot must be 1 or greater.")
    chain = get_fallback_chain(config)
    index = slot - 1
    if index >= len(chain):
        set_fallback_chain(config, chain)
        return chain
    del chain[index]
    set_fallback_chain(config, chain)
    return get_fallback_chain(config)
