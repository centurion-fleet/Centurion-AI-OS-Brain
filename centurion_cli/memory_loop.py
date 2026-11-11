#!/usr/bin/env python3
"""The memory loop — collect, curate, recall.

Three failures this closes, all measured on 11 Nov 2026:

  * the hot cache sat at 3,193/3,200 chars — 100% full, 31 entries — so a new
    fact displaced an old one or fell off silently;
  * nothing converted a day's work into a durable fact: the consolidation job
    had been dead since 26 Oct, so sixteen days of work taught the next
    instance nothing;
  * recall fired only when a message happened to contain the right word.

`collect` is for an agent to distil (a script cannot tell "stopped mattering"
from "load-bearing"). `pressure` is deterministic. Neither writes: the agent
proposes, the owner's Vault decides.
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

MAX_CHARS = 14_000
PER_MESSAGE = 900


def centurion_home() -> Path:
    try:
        from centurion_constants import get_centurion_home

        return Path(get_centurion_home())
    except Exception:
        return Path(os.environ.get("CENTURION_HOME", Path.home() / ".centurion"))


def state_db() -> Path:
    return centurion_home() / "state.db"


def _rows(hours: int):
    db = state_db()
    if not db.exists():
        return []
    since = (datetime.now(timezone.utc) - timedelta(hours=hours)).timestamp()
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=10)
    try:
        con.row_factory = sqlite3.Row
        return con.execute(
            """
            SELECT m.session_id, m.role, m.content, m.timestamp
            FROM messages m
            WHERE m.timestamp >= ?
              AND m.role IN ('user', 'assistant')
              AND m.content IS NOT NULL
              AND length(m.content) > 40
            ORDER BY m.timestamp
            """,
            (since,),
        ).fetchall()
    finally:
        con.close()


def collect(hours: int = 24, max_chars: int = MAX_CHARS) -> str:
    """A digest of the window, small enough to distil in one pass."""
    rows = _rows(hours)
    if not rows:
        return ""

    by_session: dict[str, list] = {}
    for r in rows:
        by_session.setdefault(r["session_id"], []).append(r)

    out: list[str] = []
    used = 0
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out.append(f"# Work digest — last {hours}h, window ending {stamp}")
    out.append(f"# {len(rows)} messages across {len(by_session)} sessions\n")

    for sid, msgs in by_session.items():
        when = datetime.fromtimestamp(msgs[0]["timestamp"], timezone.utc).strftime("%d %b %H:%M")
        block = [f"## session {sid[:18]} · started {when} · {len(msgs)} msgs"]
        for m in msgs:
            text = " ".join((m["content"] or "").split())
            if len(text) > PER_MESSAGE:
                text = text[:PER_MESSAGE] + " …[cut]"
            block.append(f"- {m['role']}: {text}")
        chunk = "\n".join(block)
        if used + len(chunk) > max_chars:
            out.append("\n# …window truncated; older sessions omitted")
            break
        out.append(chunk)
        used += len(chunk)
    return "\n".join(out)


def pressure() -> dict:
    """Hot-cache headroom, in the same terms the curator uses."""
    mem = centurion_home() / "memories"
    out = {}
    for name, cap in (("MEMORY.md", 3200), ("USER.md", 3600)):
        p = mem / name
        chars = len(p.read_text(encoding="utf-8")) if p.exists() else 0
        out[name] = {
            "chars": chars,
            "cap": cap,
            "pct": round(100 * chars / cap, 1) if cap else 0.0,
        }
    return out


def pressure_report(silent_under: int | None = None) -> str:
    p = pressure()
    worst = max(v["pct"] for v in p.values()) if p else 0
    if silent_under is not None and worst < silent_under:
        return ""
    lines = [f"Memory pressure — worst {worst}% of cap"]
    for name, v in p.items():
        flag = "  <-- demote" if v["pct"] >= 95 else ""
        lines.append(f"  {name:10s} {v['chars']:5d}/{v['cap']}  {v['pct']:5.1f}%{flag}")
    if worst >= 95:
        lines.append(
            "\nRun: centurion memory curate --propose, then move the ranked "
            "entries to COLD.md leaving a pointer line behind."
        )
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="centurion memory", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("collect", help="print a digest of recent sessions for distillation")
    c.add_argument("--hours", type=int, default=24)
    c.add_argument("--max-chars", type=int, default=MAX_CHARS)

    p = sub.add_parser("pressure", help="hot-cache headroom; silent below --silent-under")
    p.add_argument("--silent-under", type=int, default=None,
                   help="print nothing when the worst store is under this percent")
    p.add_argument("--json", action="store_true")

    a = ap.parse_args(argv)
    if a.cmd == "collect":
        text = collect(a.hours, a.max_chars)
        if not text:
            print(f"No messages in the last {a.hours}h.", file=sys.stderr)
            return 0
        print(text)
        return 0

    if a.cmd == "pressure":
        if a.json:
            print(json.dumps(pressure(), indent=2))
            return 0
        report = pressure_report(a.silent_under)
        if report:
            print(report)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
