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


def structured_to_markdown(fields: dict[str, Any]) -> str:
    """Render iOS-style structured fields to the managed SOUL.md section."""
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

    return {
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
    path = soul_md_path()
    markdown = path.read_text(encoding="utf-8") if path.exists() else ""
    structured = markdown_to_structured(markdown)
    structured["path"] = str(path)
    structured["exists"] = path.exists()
    return structured


def write_soul(fields: dict[str, Any] | None = None, *, markdown: str | None = None) -> dict[str, Any]:
    """Write SOUL.md from structured fields and/or raw markdown override."""
    path = soul_md_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    if markdown is not None and fields:
        # Prefer structured merge when both provided — structured wins for managed block.
        content = merge_structured_into_soul_md(fields, existing=markdown)
    elif markdown is not None:
        content = markdown
    elif fields is not None:
        existing = path.read_text(encoding="utf-8") if path.exists() else ""
        content = merge_structured_into_soul_md(fields, existing=existing)
    else:
        raise ValueError("soul_put requires structured fields or markdown")

    path.write_text(content, encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return read_soul()


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
