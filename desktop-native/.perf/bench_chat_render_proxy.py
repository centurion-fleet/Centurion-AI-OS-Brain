#!/usr/bin/env python3
"""WS3 B3 — structural chat-render proxy (runs on any OS).

Estimates GTK widget pressure for a 100-message prose+code corpus before/after
paragraph coalescing (mirrors chat_page coalesce_paragraph_blocks).

Does NOT replace Fedora A1 interaction timing — see README-ws3-chat.md.
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path

CODE_FENCE = re.compile(r"```[\w.-]*\n.*?```", re.DOTALL)
RULE = re.compile(r"(?m)^---\s*$")


def split_blocks(md: str) -> list[tuple[str, str]]:
    """Return list of (kind, text) where kind in paragraph|code|rule."""
    blocks: list[tuple[str, str]] = []
    pos = 0
    for m in CODE_FENCE.finditer(md):
        if m.start() > pos:
            chunk = md[pos : m.start()]
            blocks.extend(_paragraphs_and_rules(chunk))
        blocks.append(("code", m.group(0)))
        pos = m.end()
    if pos < len(md):
        blocks.extend(_paragraphs_and_rules(md[pos:]))
    return blocks


def _paragraphs_and_rules(chunk: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for part in RULE.split(chunk):
        if out and part is not None:
            # RULE.split removes separators; re-insert rule markers between parts
            pass
        text = part.strip()
        if not text:
            continue
        # headings stay as their own "paragraph" (not coalesced with prose)
        for para in re.split(r"\n\s*\n", text):
            p = para.strip()
            if p:
                kind = "heading" if p.startswith("#") else "paragraph"
                out.append((kind, p))
    return out


def coalesce(blocks: list[tuple[str, str]]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for kind, text in blocks:
        if (
            out
            and out[-1][0] == "paragraph"
            and kind == "paragraph"
        ):
            prev_k, prev_t = out[-1]
            out[-1] = (prev_k, prev_t + "\n\n" + text)
        else:
            out.append((kind, text))
    return out


def corpus_message(i: int) -> str:
    code = ""
    if i % 5 == 0:
        code = "```python\n" + ("print('hello')\n" * 40) + "```\n\n"
    return (
        f"## Turn {i}\n\n"
        f"First paragraph about topic {i}.\n\n"
        f"Second paragraph continues the thought.\n\n"
        f"- item a\n- item b\n- item c\n\n"
        f"{code}"
    )


def main() -> None:
    before = after = before_paras = after_paras = 0
    t0 = time.perf_counter()
    for i in range(100):
        md = corpus_message(i)
        raw = split_blocks(md)
        coal = coalesce(raw)
        before += len(raw)
        after += len(coal)
        before_paras += sum(1 for k, _ in raw if k == "paragraph")
        after_paras += sum(1 for k, _ in coal if k == "paragraph")
    ms = (time.perf_counter() - t0) * 1000.0
    reduction = 0.0 if before == 0 else 100.0 * (before - after) / before
    result = {
        "kind": "ws3_chat_render_proxy",
        "messages": 100,
        "before_blocks": before,
        "after_blocks": after,
        "before_paragraphs": before_paras,
        "after_paragraphs": after_paras,
        "block_reduction_pct": round(reduction, 1),
        "parse_ms": round(ms, 1),
        "notes": [
            "Structural proxy for B1.1 coalesce — not A1 interaction latency.",
            "INITIAL_VISIBLE_MESSAGES=50 caps ListStore on resume (B2).",
            "Large code fences lazy-build Label until Show (B1.2).",
        ],
    }
    out = Path(__file__).resolve().parent / "ws3-chat-proxy.json"
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
