"""What this Centurion is working on, and what it is able to do.

Two Centurions linked on one network still leave both owners asking the same
question: what is actually in progress, on which machine, right now? The answer
already exists — it is the owner's own mission stack. This module reads it and
reduces it to a short, honest list that travels inside a fleet check-in.

It answers a second question too, and that one is what makes two Centurions able
to divide work between them: *what is this one able to do?* That answer also
already exists — it is the skill library on disk. Reading it from the skills
rather than from a hand-written profile is the point: a profile drifts, the
library cannot.

Rules it will not break:

* It never invents work. If nothing is in progress it says so, rather than
  filling the board with something that looks busy.
* Reading is reading. It will not create a mission store as a side effect of
  being asked what someone is doing.
* A capability list is what we *can* do, never a claim to have done it. The two
  live in different fields on purpose.
"""

from __future__ import annotations

import os
import re
import time
from typing import Any, Callable, Optional

#: A board nobody reads is not a board. Keep it to what a human can take in.
MAX_ITEMS = 3

#: Bounds on what a *peer* may write into our records. A peer is on our network
#: and authenticated, which is not the same as trustworthy with our disk.
MAX_TEXT = 120
MAX_ITEMS_ACCEPTED = 10

#: A capability list is matched against, not read end to end — so it wants
#: breadth where the board wants brevity. Still bounded: a peer supplies it.
MAX_CAPABILITIES = 40
MAX_CAPABILITY_TEXT = 160

_FRONTMATTER_FIELD = re.compile(r"^(name|description):\s*(.+?)\s*$", re.MULTILINE)


def _version() -> str:
    try:
        from centurion_cli import __version__

        return str(__version__)
    except Exception:
        return ""


def _skills_root() -> Optional[str]:
    """Where this Centurion's skills live, if the directory exists.

    The owner's own skills win — that is the library they have built up. The
    bundled set is the fallback, for a Brain that has not added any yet.
    """
    home = os.environ.get("CENTURION_HOME") or os.path.expanduser("~/.centurion")
    candidates = [os.path.join(home, "skills")]
    try:
        from centurion_cli import __file__ as cli_file

        bundle = os.path.dirname(os.path.dirname(os.path.abspath(cli_file)))
        candidates.append(os.path.join(bundle, "skills"))
    except Exception:
        pass
    for path in candidates:
        if os.path.isdir(path):
            return path
    return None


def _frontmatter(path: str) -> dict[str, str]:
    """The ``name:`` and ``description:`` lines from a SKILL.md, if it has them."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            head = handle.read(4096)
    except OSError:
        return {}
    if not head.startswith("---"):
        return {}
    end = head.find("\n---", 3)
    block = head[3:end] if end != -1 else head[3:]
    fields: dict[str, str] = {}
    for key, value in _FRONTMATTER_FIELD.findall(block):
        fields[key] = value.strip().strip('"').strip("'")
    return fields


def _life_store_path() -> Optional[str]:
    """The mission store's path, only if it already exists."""
    try:
        from centurion_cli import life_missions

        path = str(life_missions.life_db_path())
    except Exception:
        return None
    return path if os.path.isfile(path) else None


def _load_stack() -> dict[str, Any]:
    """The owner's mission stack, or {} when there is nothing to read."""
    if _life_store_path() is None:
        return {}
    try:
        from centurion_cli import life_missions

        return life_missions.get_stack() or {}
    except Exception:
        return {}


def working_items(
    limit: int = MAX_ITEMS,
    *,
    stack_loader: Optional[Callable[[], dict[str, Any]]] = None,
) -> list[dict[str, Any]]:
    """Targets that are genuinely in progress, primary mission first.

    Only ``in_progress`` counts. A target that is not started is a plan, and a
    completed one is history; neither is what someone is doing right now.
    """
    stack = (stack_loader or _load_stack)() or {}

    missions: list[dict[str, Any]] = []
    primary = stack.get("primary")
    if isinstance(primary, dict):
        missions.append(primary)
    for mission in stack.get("supporting") or []:
        if isinstance(mission, dict):
            missions.append(mission)

    items: list[dict[str, Any]] = []
    for mission in missions:
        mission_title = str(mission.get("title") or "").strip()
        for target in mission.get("targets") or []:
            if not isinstance(target, dict):
                continue
            if str(target.get("status") or "") != "in_progress":
                continue
            items.append(
                {
                    "mission": mission_title,
                    "target": str(target.get("title") or "").strip(),
                    "target_id": str(target.get("id") or ""),
                    "status": "in_progress",
                }
            )
            if len(items) >= max(1, int(limit)):
                return items
    return items


def _fair_sample(items: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    """Trim a library to ``limit`` without letting one big category eat it all.

    A plain alphabetical cut is a silent lie: sort by category, stop at 40, and
    every skill after the first few categories is reported as absent when it is
    only reported as *late*. Round-robin across categories keeps the manifest a
    sample of the whole library rather than a prefix of the alphabet.
    """
    if len(items) <= limit:
        return items

    by_category: dict[str, list[dict[str, Any]]] = {}
    for item in items:
        by_category.setdefault(item["category"], []).append(item)

    order = sorted(by_category)
    picked: list[dict[str, Any]] = []
    depth = 0
    while len(picked) < limit:
        progressed = False
        for category in order:
            bucket = by_category[category]
            if depth < len(bucket):
                picked.append(bucket[depth])
                progressed = True
                if len(picked) >= limit:
                    break
        if not progressed:  # every bucket exhausted
            break
        depth += 1
    return picked


def capabilities(
    limit: int = MAX_CAPABILITIES,
    *,
    root: Optional[str] = None,
) -> list[dict[str, Any]]:
    """What this Centurion can actually do — read from its own skill library.

    This is the list a peer matches work against when the two of them divide a
    job: not what I am doing now (``working_items``), but what I am *able* to do.
    Sourced from the skills on disk so it cannot drift from reality the way a
    hand-written profile can.

    An empty list is a real answer and is reported as one. It means this Brain
    carries no skills yet — not that it is unable to work.
    """
    base = root if root is not None else _skills_root()
    if not base or not os.path.isdir(base):
        return []

    found: list[dict[str, Any]] = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith((".", "_"))]
        if "SKILL.md" not in filenames:
            continue
        fields = _frontmatter(os.path.join(dirpath, "SKILL.md"))
        name = (fields.get("name") or "").strip() or os.path.basename(dirpath)
        if not name:
            continue
        relative = os.path.relpath(dirpath, base)
        parts = relative.split(os.sep)
        # A skill one level down under a category dir carries that category;
        # a top-level skill has none.
        category = parts[0] if len(parts) > 1 else ""
        found.append(
            {
                "name": _clean_text(name, MAX_CAPABILITY_TEXT),
                "category": _clean_text(category, MAX_CAPABILITY_TEXT),
                "description": _clean_text(fields.get("description"), MAX_CAPABILITY_TEXT),
            }
        )

    found.sort(key=lambda item: (item["category"], item["name"]))
    return _fair_sample(found, max(1, int(limit)))


def local_activity(limit: int = MAX_ITEMS) -> dict[str, Any]:
    """This Centurion's identity, what it is working on, and what it can do."""
    try:
        from .identity import local_identity

        identity = local_identity()
    except Exception:
        identity = {}

    return {
        "centurion_id": str(identity.get("centurion_id") or ""),
        "name": str(identity.get("name") or "Centurion"),
        "version": _version(),
        "working_on": working_items(limit),
        "capabilities": capabilities(),
        "captured_at": time.time(),
    }


def _clean_text(value: Any, limit: int = MAX_TEXT) -> str:
    return " ".join(str(value or "").split())[:limit]


def parse_activity(raw: Any) -> dict[str, Any]:
    """Validate an activity payload that arrived from a peer.

    Returns {} for anything unusable. A malformed board must leave the peer
    listed with what we last knew, not blank it out.
    """
    if not isinstance(raw, dict):
        return {}

    items: list[dict[str, Any]] = []
    for entry in raw.get("working_on") or []:
        if not isinstance(entry, dict):
            continue
        target = _clean_text(entry.get("target"))
        if not target:
            continue
        items.append(
            {
                "mission": _clean_text(entry.get("mission")),
                "target": target,
                "target_id": _clean_text(entry.get("target_id")),
                "status": _clean_text(entry.get("status")) or "in_progress",
            }
        )
        if len(items) >= MAX_ITEMS_ACCEPTED:
            break

    caps: list[dict[str, Any]] = []
    for entry in raw.get("capabilities") or []:
        if not isinstance(entry, dict):
            continue
        cap_name = _clean_text(entry.get("name"), MAX_CAPABILITY_TEXT)
        if not cap_name:
            continue
        caps.append(
            {
                "name": cap_name,
                "category": _clean_text(entry.get("category"), MAX_CAPABILITY_TEXT),
                "description": _clean_text(entry.get("description"), MAX_CAPABILITY_TEXT),
            }
        )
        if len(caps) >= MAX_CAPABILITIES:
            break

    captured = raw.get("captured_at")
    captured_at = 0.0
    if isinstance(captured, (int, float, str)):
        try:
            captured_at = float(captured)
        except (TypeError, ValueError):
            captured_at = 0.0

    return {
        "name": _clean_text(raw.get("name")),
        "version": _clean_text(raw.get("version")),
        "working_on": items,
        "capabilities": caps,
        "captured_at": captured_at,
    }


def record_peer_activity(centurion_id: str, activity: Any) -> bool:
    """Store what a peer said it is working on, and what it can do.

    Kept against the peer record so the humans can still see it after the peer
    has gone quiet — with the time it was captured, so nobody mistakes it for
    news. Returns False if the peer is not one we know.
    """
    if not centurion_id:
        return False
    parsed = parse_activity(activity)
    if not parsed:
        return False

    try:
        from .peers import FleetPeers

        peers = FleetPeers()
        peer = peers.get(centurion_id)
        if peer is None:
            return False
        peer.activity = parsed
        peers.register(peer)
        return True
    except Exception:
        return False
