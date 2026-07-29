"""Life Mission ↔ host LIFE_MISSION.md + USER.md sync for Remote apps.

iOS stores a structured ``LifeMission``; the agent must load that content so
every new conversation prioritizes the owner's mission. This module:

1. Writes a managed block to ``~/.centurion/LIFE_MISSION.md``
2. Upserts a durable entry in ``~/.centurion/memories/USER.md``
3. Exposes structured fields for Remote get/put

Prompt injection lives in ``agent/system_prompt.py`` via
``build_mission_guidance()``.
"""

from __future__ import annotations

import re
from typing import Any

from centurion_constants import get_centurion_home

_BEGIN = "<!-- centurion:mission-structured:begin -->"
_END = "<!-- centurion:mission-structured:end -->"
_USER_MARKER = "<!-- centurion:life-mission-user -->"
_SECTION_RE = re.compile(r"^##\s+(?P<title>.+?)\s*$", re.MULTILINE)
ENTRY_DELIMITER = "\n§\n"


def life_mission_md_path():
    return get_centurion_home() / "LIFE_MISSION.md"


def user_md_path():
    return get_centurion_home() / "memories" / "USER.md"


def _as_str_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        text = value.strip()
        return [text] if text else []
    out: list[str] = []
    if isinstance(value, (list, tuple)):
        for item in value:
            if isinstance(item, dict):
                title = str(item.get("title") or item.get("name") or "").strip()
                desc = str(item.get("description") or "").strip()
                if title and desc:
                    out.append(f"{title}: {desc}")
                elif title:
                    out.append(title)
                continue
            text = str(item).strip()
            if text:
                out.append(text)
    return out


def _profile_dict(fields: dict[str, Any]) -> dict[str, Any]:
    profile = fields.get("profile")
    if isinstance(profile, dict):
        return profile
    return {}


def structured_to_markdown(fields: dict[str, Any]) -> str:
    """Render iOS-style Life Mission fields to the managed LIFE_MISSION.md block."""
    statement = str(fields.get("statement") or fields.get("missionStatement") or "").strip()
    mission_id = str(fields.get("id") or fields.get("mission_id") or "").strip()
    targets = fields.get("targets") or fields.get("commitments") or []
    profile = _profile_dict(fields)

    why = str(profile.get("whyThisMission") or profile.get("why_this_mission") or "").strip()
    story = str(profile.get("yourStory") or profile.get("your_story") or "").strip()
    personality = str(
        profile.get("yourPersonality") or profile.get("your_personality") or ""
    ).strip()
    work_style = str(profile.get("workStyle") or profile.get("work_style") or "").strip()
    decision_style = str(
        profile.get("decisionStyle") or profile.get("decision_style") or ""
    ).strip()
    values = _as_str_list(profile.get("yourValues") or profile.get("your_values"))
    strengths = _as_str_list(profile.get("yourStrengths") or profile.get("your_strengths"))
    focus = _as_str_list(profile.get("areasOfFocus") or profile.get("areas_of_focus"))
    challenges = _as_str_list(profile.get("challenges"))
    relationships = _as_str_list(
        profile.get("keyRelationships") or profile.get("key_relationships")
    )

    target_lines: list[str] = []
    if isinstance(targets, (list, tuple)):
        for item in targets:
            if isinstance(item, dict):
                title = str(item.get("title") or "").strip()
                desc = str(item.get("description") or "").strip()
                tid = str(item.get("id") or "").strip()
                if not title:
                    continue
                line = f"- {title}"
                if desc:
                    line += f" — {desc}"
                if tid:
                    line += f" (id: {tid})"
                target_lines.append(line)
            else:
                text = str(item).strip()
                if text:
                    target_lines.append(f"- {text}")

    lines = [
        _BEGIN,
        "# Life Mission",
        "",
        "Managed by Centurion Remote. Edits from the phone update this block. "
        "Content outside the markers is preserved.",
        "",
    ]
    if mission_id:
        lines.extend([f"<!-- mission_id: {mission_id} -->", ""])
    if statement:
        lines.extend(["## Statement", "", statement, ""])
    if why:
        lines.extend(["## Why This Mission", "", why, ""])
    if target_lines:
        lines.extend(["## Commitments", ""])
        lines.extend(target_lines)
        lines.append("")
    if story:
        lines.extend(["## Your Story", "", story, ""])
    if values:
        lines.extend(["## Values", ""])
        lines.extend(f"- {v}" for v in values)
        lines.append("")
    if personality:
        lines.extend(["## Personality", "", personality, ""])
    if strengths:
        lines.extend(["## Strengths", ""])
        lines.extend(f"- {s}" for s in strengths)
        lines.append("")
    if focus:
        lines.extend(["## Areas of Focus", ""])
        lines.extend(f"- {f}" for f in focus)
        lines.append("")
    if work_style:
        lines.extend(["## Work Style", "", work_style, ""])
    if decision_style:
        lines.extend(["## Decision Style", "", decision_style, ""])
    if challenges:
        lines.extend(["## Challenges", ""])
        lines.extend(f"- {c}" for c in challenges)
        lines.append("")
    if relationships:
        lines.extend(["## Key Relationships", ""])
        lines.extend(f"- {r}" for r in relationships)
        lines.append("")
    lines.append(_END)
    return "\n".join(lines).rstrip() + "\n"


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
        body = re.sub(r"^#.*$", "", markdown or "", count=1, flags=re.MULTILINE)
        body = body.replace(_BEGIN, "").replace(_END, "").strip()
        body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        return {"statement": body} if body else {}

    sections: dict[str, str] = {}
    for idx, match in enumerate(matches):
        title = match.group("title").strip().lower()
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(markdown)
        body = markdown[start:end].strip()
        body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        sections[title] = body
    return sections


def extract_managed_block(markdown: str) -> str | None:
    if not markdown:
        return None
    start = markdown.find(_BEGIN)
    end = markdown.find(_END)
    if start < 0 or end < 0 or end <= start:
        return None
    return markdown[start + len(_BEGIN) : end].strip()


def markdown_to_structured(markdown: str) -> dict[str, Any]:
    managed = extract_managed_block(markdown) or markdown
    sections = _split_sections(managed)
    mid = ""
    m = re.search(r"<!--\s*mission_id:\s*(.+?)\s*-->", markdown or "")
    if m:
        mid = m.group(1).strip()

    commitments_raw = sections.get("commitments", "")
    targets: list[dict[str, str]] = []
    for line in commitments_raw.splitlines():
        stripped = line.strip()
        if not stripped.startswith(("- ", "* ")):
            continue
        body = stripped[2:].strip()
        tid = ""
        id_m = re.search(r"\(id:\s*([^)]+)\)\s*$", body)
        if id_m:
            tid = id_m.group(1).strip()
            body = body[: id_m.start()].strip()
        if " — " in body:
            title, desc = body.split(" — ", 1)
        else:
            title, desc = body, ""
        targets.append({"id": tid, "title": title.strip(), "description": desc.strip()})

    profile = {
        "whyThisMission": sections.get("why this mission", ""),
        "yourStory": sections.get("your story", ""),
        "yourPersonality": sections.get("personality", ""),
        "yourValues": _bullets(sections.get("values", "")),
        "yourStrengths": _bullets(sections.get("strengths", "")),
        "areasOfFocus": _bullets(sections.get("areas of focus", "")),
        "workStyle": sections.get("work style", ""),
        "decisionStyle": sections.get("decision style", ""),
        "challenges": _bullets(sections.get("challenges", "")),
        "keyRelationships": _bullets(sections.get("key relationships", "")),
    }

    return {
        "id": mid,
        "statement": sections.get("statement", "").strip(),
        "targets": targets,
        "profile": profile,
        "markdown": markdown or "",
    }


def merge_structured_into_mission_md(fields: dict[str, Any], existing: str | None = None) -> str:
    if existing is None:
        path = life_mission_md_path()
        existing = path.read_text(encoding="utf-8") if path.exists() else ""

    managed = structured_to_markdown(fields)
    start = existing.find(_BEGIN)
    end = existing.find(_END)
    if start >= 0 and end > start:
        return existing[:start] + managed + existing[end + len(_END) :].lstrip("\n")
    if existing.strip():
        return existing.rstrip() + "\n\n" + managed
    return managed


def _user_entry_from_fields(fields: dict[str, Any]) -> str:
    statement = str(fields.get("statement") or "").strip()
    profile = _profile_dict(fields)
    why = str(profile.get("whyThisMission") or "").strip()
    values = _as_str_list(profile.get("yourValues"))
    targets = fields.get("targets") or []
    commitment_titles: list[str] = []
    if isinstance(targets, (list, tuple)):
        for item in targets:
            if isinstance(item, dict):
                t = str(item.get("title") or "").strip()
                if t:
                    commitment_titles.append(t)
            else:
                t = str(item).strip()
                if t:
                    commitment_titles.append(t)

    parts = [
        _USER_MARKER,
        "Life Mission (synced from Sovereign Remote — treat as authoritative):",
    ]
    if statement:
        parts.append(f"Statement: {statement}")
    if why:
        parts.append(f"Why: {why}")
    if values:
        parts.append("Values: " + "; ".join(values))
    if commitment_titles:
        parts.append("Active commitments: " + "; ".join(commitment_titles[:12]))
    return "\n".join(parts)


def upsert_user_md_mission(fields: dict[str, Any]) -> None:
    """Replace or insert the managed Life Mission entry in memories/USER.md."""
    path = user_md_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    entries = [e.strip() for e in existing.split(ENTRY_DELIMITER) if e.strip()] if existing.strip() else []
    new_entry = _user_entry_from_fields(fields)
    replaced = False
    out: list[str] = []
    for entry in entries:
        if _USER_MARKER in entry:
            out.append(new_entry)
            replaced = True
        else:
            out.append(entry)
    if not replaced:
        # Prefer mission near the top of USER profile.
        out.insert(0, new_entry)
    path.write_text(ENTRY_DELIMITER.join(out) + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass


def read_mission() -> dict[str, Any]:
    path = life_mission_md_path()
    markdown = path.read_text(encoding="utf-8") if path.exists() else ""
    structured = markdown_to_structured(markdown)
    structured["path"] = str(path)
    structured["exists"] = path.exists()
    return structured


def write_mission(fields: dict[str, Any] | None = None, *, markdown: str | None = None) -> dict[str, Any]:
    path = life_mission_md_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    if markdown is not None and fields:
        content = merge_structured_into_mission_md(fields, existing=markdown)
    elif markdown is not None:
        content = markdown
        fields = markdown_to_structured(markdown)
    elif fields is not None:
        existing = path.read_text(encoding="utf-8") if path.exists() else ""
        content = merge_structured_into_mission_md(fields, existing=existing)
    else:
        raise ValueError("mission_put requires structured fields or markdown")

    path.write_text(content, encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass

    if fields:
        upsert_user_md_mission(fields)
    return read_mission()


def build_mission_guidance(config: dict[str, Any] | None = None) -> str:
    """Stable system-prompt guidance so Mission shapes agent performance.

    Prefers the offline life.db Mission Stack (primary + supporting) when
    present; falls back to legacy LIFE_MISSION.md sync fields.
    """
    del config  # reserved for future config-gated behavior
    stack_block = _guidance_from_life_stack()
    if stack_block:
        return stack_block

    mission = read_mission()
    statement = str(mission.get("statement") or "").strip()
    if not statement and not mission.get("exists"):
        return ""

    profile = mission.get("profile") if isinstance(mission.get("profile"), dict) else {}
    why = str(profile.get("whyThisMission") or "").strip()
    values = profile.get("yourValues") if isinstance(profile.get("yourValues"), list) else []
    targets = mission.get("targets") if isinstance(mission.get("targets"), list) else []

    lines = [
        "LIFE MISSION (authoritative — shape every reply and plan toward this):",
        f"- Statement: {statement or '(not set yet — help the owner clarify when relevant)'}",
    ]
    if why:
        lines.append(f"- Why it matters: {why}")
    if values:
        lines.append("- Values: " + "; ".join(str(v) for v in values if str(v).strip()))
    if targets:
        lines.append("- Commitments:")
        for t in targets[:12]:
            if isinstance(t, dict):
                title = str(t.get("title") or "").strip()
                desc = str(t.get("description") or "").strip()
                if title and desc:
                    lines.append(f"  • {title} — {desc}")
                elif title:
                    lines.append(f"  • {title}")
    lines.extend(
        [
            "- Prioritize actions and advice that advance this Life Mission and its commitments.",
            "- Do not contradict the owner's values or the Sovereign Soul never-do rules.",
            "- When the owner is off-mission, gently reconnect work to this north star.",
            "- Persist Mission/Target changes with life_missions (local life.db) — never portal tokens.",
        ]
    )
    return "\n".join(lines)


def _guidance_from_life_stack() -> str:
    """Build north-star text from life.db stack when a primary mission exists."""
    try:
        from centurion_cli.life_missions import get_stack
    except Exception:
        return ""
    try:
        stack = get_stack()
    except Exception:
        return ""
    primary = stack.get("primary") if isinstance(stack, dict) else None
    if not isinstance(primary, dict):
        return ""
    statement = str(primary.get("statement") or primary.get("title") or "").strip()
    title = str(primary.get("title") or "").strip()
    why = str(primary.get("why") or "").strip()
    purpose = str(primary.get("purpose") or "").strip()
    profile = primary.get("profile") if isinstance(primary.get("profile"), dict) else {}
    if not why:
        why = str(profile.get("whyThisMission") or "").strip()
    values = profile.get("yourValues") if isinstance(profile.get("yourValues"), list) else []
    targets = primary.get("targets") if isinstance(primary.get("targets"), list) else []
    supporting = stack.get("supporting") if isinstance(stack.get("supporting"), list) else []

    lines = [
        "LIFE MISSION STACK (authoritative — offline life.db on this Brain):",
        f"- Primary: {title or '(untitled)'}",
        f"- Statement: {statement or '(not set yet — help the owner clarify when relevant)'}",
    ]
    if why:
        lines.append(f"- Why: {why}")
    if purpose:
        lines.append(f"- Purpose: {purpose}")
    if values:
        lines.append("- Values: " + "; ".join(str(v) for v in values if str(v).strip()))
    if targets:
        lines.append("- Target sequence (Must Do / Should Do / Nice to Do):")
        type_label = {
            "essential": "Must Do",
            "shouldHave": "Should Do",
            "niceToHave": "Nice to Do",
        }
        for t in targets[:16]:
            if not isinstance(t, dict):
                continue
            ttitle = str(t.get("title") or "").strip()
            if not ttitle:
                continue
            label = type_label.get(str(t.get("target_type") or ""), "Target")
            status = str(t.get("status") or "").strip()
            desc = str(t.get("description") or "").strip()
            bit = f"  • [{label}] {ttitle}"
            if status:
                bit += f" ({status})"
            if desc:
                bit += f" — {desc}"
            lines.append(bit)
    if supporting:
        lines.append("- Supporting missions:")
        for m in supporting[:8]:
            if isinstance(m, dict):
                mt = str(m.get("title") or "").strip()
                if mt:
                    lines.append(f"  • {mt}")
    lines.extend(
        [
            "- Prioritize actions that advance the primary and active supporting missions.",
            "- Do not contradict the owner's values or the Sovereign Soul never-do rules.",
            "- Persist changes with life_missions only — never ask for Portal / ctk_proj tokens.",
            "- Reviewable proposals belong in the plans tool, not portal Mission Control.",
        ]
    )
    return "\n".join(lines)
