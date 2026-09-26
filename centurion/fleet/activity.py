"""What this Centurion is working on, in a form a peer — and a human — can read.

Two Centurions linked on one network still leave both owners asking the same
question: what is actually in progress, on which machine, right now? The answer
already exists — it is the owner's own mission stack. This module reads it and
reduces it to a short, honest list that travels inside a fleet check-in.

Two rules it will not break:

* It never invents work. If nothing is in progress it says so, rather than
  filling the board with something that looks busy.
* Reading is reading. It will not create a mission store as a side effect of
  being asked what someone is doing.
"""

from __future__ import annotations

import os
import time
from typing import Any, Callable, Optional

#: A board nobody reads is not a board. Keep it to what a human can take in.
MAX_ITEMS = 3

#: Bounds on what a *peer* may write into our records. A peer is on our network
#: and authenticated, which is not the same as trustworthy with our disk.
MAX_TEXT = 120
MAX_ITEMS_ACCEPTED = 10


def _version() -> str:
    try:
        from centurion_cli import __version__

        return str(__version__)
    except Exception:
        return ""


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


def local_activity(limit: int = MAX_ITEMS) -> dict[str, Any]:
    """This Centurion's identity plus what it is working on right now."""
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
        "captured_at": time.time(),
    }


def _clean_text(value: Any) -> str:
    return " ".join(str(value or "").split())[:MAX_TEXT]


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
        "captured_at": captured_at,
    }


def record_peer_activity(centurion_id: str, activity: Any) -> bool:
    """Store what a peer said it is working on.

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
