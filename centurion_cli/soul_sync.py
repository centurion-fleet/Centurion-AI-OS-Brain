"""Structured Soul document ↔ host SOUL.md sync for Remote apps.

iOS stores a structured ``SoulDocument``; the agent loads freeform
``~/.centurion/SOUL.md``. This module renders structured fields into a
Centurion-managed markdown block and parses that block back out, while
preserving any user markdown outside the managed markers.
"""

from __future__ import annotations

import re
from typing import Any

from centurion_constants import get_centurion_home

_BEGIN = "<!-- centurion:soul-structured:begin -->"
_END = "<!-- centurion:soul-structured:end -->"

_SECTION_RE = re.compile(
    r"^##\s+(?P<title>.+?)\s*$",
    re.MULTILINE,
)


def soul_md_path():
    return get_centurion_home() / "SOUL.md"


def souls_dir_path():
    """Fleet deploy writes per-Centurion docs here (``*_SOUL.md``)."""
    return get_centurion_home() / "souls"


def is_generic_seed_soul(markdown: str) -> bool:
    """True when SOUL.md is still the product default, not an owner Soul."""
    text = (markdown or "").strip()
    if not text:
        return True
    lower = text.lower()
    # Legacy first-run seed (pre-structured markers).
    if lower.startswith("you are centurion ai os"):
        return True
    # Current DEFAULT_SOUL_MD — managed block whose ## Name is Centurion and
    # personality still describes the product default.
    has_managed = _BEGIN in text and _END in text
    if has_managed and "your sovereign's soul" in lower:
        from agent.prompt_builder import (
            _clean_display_name,
            _is_usable_personal_name,
            resolve_centurion_display_name,
        )

        structured = markdown_to_structured(text)
        name = _clean_display_name(str(structured.get("name") or ""))
        if _is_usable_personal_name(name):
            return False
        # Prose may still carry a personal name outside the managed block.
        if _is_usable_personal_name(resolve_centurion_display_name(text)):
            return False
        personality = str(structured.get("personalitySummary") or "").lower()
        if "centurion ai os" in personality or "unless the owner renames you" in personality:
            return True
        if len(text) < 900 and "centurion ai os" in lower:
            return True
    return False


def list_fleet_soul_files() -> list:
    """Return ``souls/*_SOUL.md`` paths, richest (largest) first."""
    root = souls_dir_path()
    if not root.is_dir():
        return []
    files = [p for p in root.glob("*_SOUL.md") if p.is_file()]
    files.sort(key=lambda p: p.stat().st_size if p.exists() else 0, reverse=True)
    return files


def _read_soul_file(path) -> str:
    try:
        return path.read_text(encoding="utf-8") if path.is_file() else ""
    except OSError:
        return ""


def resolve_authoritative_soul_markdown() -> tuple[str, str, str]:
    """Pick the Soul body for the *active* CENTURION_HOME only.

    Policy (one Soul per profile): never borrow from the default home into a
    named profile. Settings and Chat both edit/read this home's ``SOUL.md``.
    Within the same home, a richer ``souls/*_SOUL.md`` (fleet deploy) may still
    be promoted into primary.

    Returns ``(markdown, path, source)`` where source is ``soul_md``,
    ``fleet_souls``, or ``empty``.
    """
    primary = soul_md_path()
    primary_text = _read_soul_file(primary)

    if primary_text.strip() and not is_generic_seed_soul(primary_text):
        return primary_text, str(primary), "soul_md"

    for fleet_path in list_fleet_soul_files():
        fleet_text = _read_soul_file(fleet_path)
        if not fleet_text.strip() or is_generic_seed_soul(fleet_text):
            continue
        return fleet_text, str(fleet_path), "fleet_souls"

    if primary_text.strip():
        return primary_text, str(primary), "soul_md"
    return "", str(primary), "empty"


def promote_authoritative_soul_to_primary() -> bool:
    """If this home's SOUL.md is still the seed, promote same-home fleet Soul.

    Does **not** copy from ``~/.centurion`` into a sticky profile — each
    profile owns its own Soul (save Titus in Settings while that profile is
    active).
    """
    markdown, _path, source = resolve_authoritative_soul_markdown()
    if source != "fleet_souls" or not markdown.strip():
        return False
    primary = soul_md_path()
    existing = _read_soul_file(primary)
    if existing.strip() == markdown.strip():
        return False
    primary.parent.mkdir(parents=True, exist_ok=True)
    if existing.strip():
        backup = primary.with_name("SOUL.md.bak")
        try:
            backup.write_text(existing, encoding="utf-8")
        except OSError:
            pass
    primary.write_text(markdown, encoding="utf-8")
    try:
        primary.chmod(0o600)
    except OSError:
        pass
    _persist_agent_name(markdown, None)
    _invalidate_cached_system_prompts()
    return True


def ensure_personal_name_on_disk(markdown: str | None = None) -> str:
    """If Soul prose has a personal name but ## Name / agent_name do not, heal disk."""
    from agent.prompt_builder import (
        _clean_display_name,
        _is_usable_personal_name,
        resolve_centurion_display_name,
    )

    path = soul_md_path()
    if markdown is None:
        try:
            markdown = path.read_text(encoding="utf-8") if path.exists() else ""
        except OSError:
            markdown = ""
    resolved = resolve_centurion_display_name(markdown)
    if not _is_usable_personal_name(resolved):
        return markdown or ""

    structured = markdown_to_structured(markdown or "")
    structured = _enrich_structured_from_markdown(structured, markdown or "")
    current = _clean_display_name(str(structured.get("name") or ""))
    if current == resolved and "## Name" in (markdown or ""):
        _persist_agent_name(markdown, {"name": resolved})
        return markdown or ""

    # Rewrite managed ## Name so Settings + Chat share one primary document.
    fields = dict(structured)
    fields["name"] = resolved
    updated = merge_structured_into_soul_md(fields, existing=markdown or "")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(updated, encoding="utf-8")
        path.chmod(0o600)
    except OSError:
        return markdown or ""
    _persist_agent_name(updated, fields)
    _invalidate_cached_system_prompts()
    return updated


def structured_to_markdown(fields: dict[str, Any]) -> str:
    """Render iOS-style structured fields to the managed SOUL.md section."""
    name = str(fields.get("name") or fields.get("displayName") or "").strip()
    personality = str(fields.get("personalitySummary") or fields.get("personality_summary") or "").strip()
    tone = str(fields.get("tone") or "").strip()
    communication = str(
        fields.get("communicationStyle") or fields.get("communication_style") or ""
    ).strip()
    pushback = str(
        fields.get("pushbackStyle") or fields.get("pushback_style") or ""
    ).strip()
    uncertainty = str(
        fields.get("uncertaintyStyle") or fields.get("uncertainty_style") or ""
    ).strip()
    response_length = str(
        fields.get("responseLength") or fields.get("response_length") or ""
    ).strip()
    always_do = _as_str_list(fields.get("alwaysDo") or fields.get("always_do"))
    never_do = _as_str_list(fields.get("neverDo") or fields.get("never_do"))

    lines = [
        _BEGIN,
        "# Your Sovereign's Soul",
        "",
        "Managed by Centurion Remote. Edits from the phone or Desktop Settings "
        "update this block. Content outside the markers is preserved.",
        "",
    ]
    if name:
        lines.extend(["## Name", "", name, ""])
    if personality:
        lines.extend(["## Personality", "", personality, ""])
    if tone:
        lines.extend(["## Tone", "", tone, ""])
    if communication:
        lines.extend(["## Communication Style", "", communication, ""])
    if pushback:
        lines.extend(["## Pushback Style", "", pushback, ""])
    if always_do:
        lines.extend(["## Always Do", ""])
        lines.extend(f"- {item}" for item in always_do)
        lines.append("")
    if never_do:
        lines.extend(["## Never Do", ""])
        lines.extend(f"- {item}" for item in never_do)
        lines.append("")
    if uncertainty:
        lines.extend(["## Uncertainty", "", uncertainty, ""])
    if response_length:
        lines.extend(["## Response Length", "", response_length, ""])
    lines.append(_END)
    return "\n".join(lines).rstrip() + "\n"


def markdown_to_structured(markdown: str) -> dict[str, Any]:
    """Parse managed (or whole-file) markdown into structured Soul fields."""
    managed = extract_managed_block(markdown) or markdown
    sections = _split_sections(managed)

    def body(title: str) -> str:
        return sections.get(title.lower(), "").strip()

    name = body("name")
    # First line of a freeform SOUL (no ## Name) may still be a short name
    # when users wrote "You are Titus..." — leave extraction to prompt_builder.

    return {
        "name": name,
        "personalitySummary": body("personality"),
        "tone": body("tone"),
        "communicationStyle": body("communication style"),
        "pushbackStyle": body("pushback style"),
        "alwaysDo": _bullets(body("always do")),
        "neverDo": _bullets(body("never do")),
        "uncertaintyStyle": body("uncertainty"),
        "responseLength": body("response length"),
        "markdown": markdown or "",
    }


def extract_managed_block(markdown: str) -> str | None:
    if not markdown:
        return None
    start = markdown.find(_BEGIN)
    end = markdown.find(_END)
    if start < 0 or end < 0 or end <= start:
        return None
    # Exclude the marker lines themselves from the parsed body.
    inner_start = start + len(_BEGIN)
    return markdown[inner_start:end].strip()


def merge_structured_into_soul_md(fields: dict[str, Any], existing: str | None = None) -> str:
    """Replace or append the managed block in existing SOUL.md content."""
    if existing is None:
        path = soul_md_path()
        existing = path.read_text(encoding="utf-8") if path.exists() else ""

    managed = structured_to_markdown(fields)
    start = existing.find(_BEGIN)
    end = existing.find(_END)
    if start >= 0 and end > start:
        return existing[:start] + managed + existing[end + len(_END) :].lstrip("\n")
    if existing.strip():
        return existing.rstrip() + "\n\n" + managed
    return managed


def read_soul() -> dict[str, Any]:
    """Read host SOUL.md and return markdown + structured fields."""
    try:
        from centurion_cli.config import ensure_centurion_home

        ensure_centurion_home()
    except Exception:
        pass
    # Fleet deploy may have left the real Soul under souls/ while SOUL.md
    # stayed the product seed — promote so Settings and Chat share one file.
    try:
        promote_authoritative_soul_to_primary()
    except Exception:
        pass
    path = soul_md_path()
    markdown = path.read_text(encoding="utf-8") if path.exists() else ""
    try:
        markdown = ensure_personal_name_on_disk(markdown)
    except Exception:
        pass
    structured = markdown_to_structured(markdown)
    structured = _enrich_structured_from_markdown(structured, markdown)
    structured["path"] = str(path)
    structured["exists"] = path.exists()
    structured["source"] = "soul_md" if markdown.strip() else "empty"
    return structured


def _enrich_structured_from_markdown(
    structured: dict[str, Any], markdown: str
) -> dict[str, Any]:
    """Fill name/personality from fleet-style SOUL.md when ## Name is absent."""
    from agent.prompt_builder import (
        _clean_display_name,
        _infer_name_from_markdown,
        _is_usable_personal_name,
    )

    out = dict(structured)
    name = _clean_display_name(str(out.get("name") or ""))
    if not _is_usable_personal_name(name):
        inferred = _infer_name_from_markdown(markdown)
        if _is_usable_personal_name(inferred):
            out["name"] = inferred
    if not str(out.get("personalitySummary") or "").strip():
        sections = _split_sections(markdown)
        for key, body in sections.items():
            if "core identity" in key:
                out["personalitySummary"] = body.strip()
                break
        if not str(out.get("personalitySummary") or "").strip():
            for key, body in sections.items():
                if "personality" in key:
                    out["personalitySummary"] = body.strip()
                    break
    out["markdown"] = markdown or out.get("markdown") or ""
    return out


def write_soul(fields: dict[str, Any] | None = None, *, markdown: str | None = None) -> dict[str, Any]:
    """Write SOUL.md from structured fields and/or raw markdown override."""
    path = soul_md_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    disk_existing = path.read_text(encoding="utf-8") if path.exists() else ""

    # Desktop Settings can open with an empty buffer when soul_get fails after
    # an update — never let that clobber a good on-disk Soul document.
    if markdown is not None and not markdown.strip() and disk_existing.strip():
        if fields:
            markdown = disk_existing
        else:
            raise ValueError(
                "Refusing to save an empty Soul document over existing content. "
                "Close Settings and try again after the Brain bridge is healthy."
            )

    # Normalize Name on every save (strip emoji etc.) so ## Name matches Chat.
    if isinstance(fields, dict) and "name" in fields:
        from agent.prompt_builder import _clean_display_name

        fields = dict(fields)
        cleaned = _clean_display_name(str(fields.get("name") or ""))
        if cleaned:
            fields["name"] = cleaned

    if markdown is not None and fields:
        # Merge structured patches onto whatever the markdown already encodes
        # so a Name-only update does not wipe Personality / rules.
        existing_fields = markdown_to_structured(markdown)
        # Freeform Souls often put the name only in prose / title — enrich
        # before merge so an empty Name field in Settings cannot erase it.
        existing_fields = _enrich_structured_from_markdown(existing_fields, markdown)
        merged = dict(existing_fields)
        for key, value in fields.items():
            if key == "markdown":
                continue
            if value is None:
                continue
            # Empty strings never overwrite — including name. An empty Name
            # box in Desktop Settings used to wipe ## Name on every Save.
            if isinstance(value, str) and not value.strip():
                continue
            merged[key] = value
        content = merge_structured_into_soul_md(merged, existing=markdown)
    elif markdown is not None:
        content = markdown
    elif fields is not None:
        content = merge_structured_into_soul_md(fields, existing=disk_existing)
    else:
        raise ValueError("soul_put requires structured fields or markdown")

    if disk_existing.strip() and not content.strip():
        raise ValueError(
            "Refusing to wipe SOUL.md. Re-open Settings or edit the file directly."
        )

    if disk_existing.strip():
        backup = path.with_name("SOUL.md.bak")
        try:
            backup.write_text(disk_existing, encoding="utf-8")
            try:
                backup.chmod(0o600)
            except OSError:
                pass
        except OSError:
            pass

    path.write_text(content, encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    _persist_agent_name(content, fields if isinstance(fields, dict) else None)
    # Soul edits must take effect on the next agent turn — drop cached
    # system prompts so continuing sessions rebuild identity from disk.
    _invalidate_cached_system_prompts()
    return read_soul()


def _persist_agent_name(content: str | None, fields: dict[str, Any] | None) -> None:
    """Keep a sticky personal name file so Brain chat always resolves it."""
    from agent.prompt_builder import _clean_display_name, _infer_name_from_markdown, agent_name_path

    name = ""
    if isinstance(fields, dict):
        name = _clean_display_name(str(fields.get("name") or ""))
    if not name and content:
        try:
            name = _clean_display_name(str(markdown_to_structured(content).get("name") or ""))
        except Exception:
            name = ""
        if not name:
            name = _infer_name_from_markdown(content)
    path = agent_name_path()
    try:
        if name:
            path.write_text(name + "\n", encoding="utf-8")
            try:
                path.chmod(0o600)
            except OSError:
                pass
        elif path.exists() and content is not None:
            # Explicit empty name in a full rewrite — leave sticky unless cleared.
            pass
    except Exception:
        pass


def _invalidate_cached_system_prompts() -> None:
    try:
        from centurion_state import SessionDB

        SessionDB().clear_system_prompts()
    except Exception:
        pass


def _as_str_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        text = value.strip()
        return [text] if text else []
    out: list[str] = []
    if isinstance(value, (list, tuple)):
        for item in value:
            text = str(item).strip()
            if text:
                out.append(text)
    return out


def _bullets(text: str) -> list[str]:
    items: list[str] = []
    for line in (text or "").splitlines():
        stripped = line.strip()
        if stripped.startswith("<!--"):
            continue
        if stripped.startswith(("- ", "* ")):
            items.append(stripped[2:].strip())
        elif stripped:
            items.append(stripped)
    return items


def _split_sections(markdown: str) -> dict[str, str]:
    matches = list(_SECTION_RE.finditer(markdown or ""))
    if not matches:
        # Treat whole body (minus title/markers) as personality if non-empty.
        body = re.sub(r"^#.*$", "", markdown or "", count=1, flags=re.MULTILINE)
        body = body.replace(_BEGIN, "").replace(_END, "").strip()
        body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        return {"personality": body} if body else {}

    sections: dict[str, str] = {}
    for idx, match in enumerate(matches):
        title = match.group("title").strip().lower()
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(markdown)
        body = markdown[start:end].strip()
        body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        sections[title] = body
    return sections
