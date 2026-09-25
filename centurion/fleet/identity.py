"""Who this Centurion is, as far as the fleet is concerned.

There was no stable identity. `CENTURION_ID` came from an environment variable
that nothing writes, so a Brain fell back to its hostname — meaning Eve would
appear in Mikki's peer list as "ships-ai" or "fedora", not as Eve. The humans
cannot direct a fleet they cannot name.

This module gives each Brain one durable identity, created once:

    ~/.centurion/fleet/identity.json
    {"centurion_id": "eve-a1b2c3", "name": "Eve"}

The name comes from the Centurion's own Soul (``## Name`` in SOUL.md), so the
fleet shows the name the owner actually gave it.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import time
from pathlib import Path
from typing import Any

_IDENTITY_FILENAME = "identity.json"


def _home() -> Path:
    base = os.environ.get("CENTURION_HOME") or os.path.expanduser("~/.centurion")
    return Path(base)


def _identity_path() -> Path:
    d = _home() / "fleet"
    d.mkdir(parents=True, exist_ok=True)
    return d / _IDENTITY_FILENAME


def _slug(value: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", value.strip().lower()).strip("-")
    return s[:40]


def soul_name() -> str:
    """The Centurion's own name from SOUL.md (``## Name``). Empty if unset.

    Deliberately tolerant: a malformed or missing Soul must not stop the fleet
    from working — it just falls back to the hostname.
    """
    for candidate in (_home() / "SOUL.md", _home() / "soul.md"):
        try:
            text = candidate.read_text(encoding="utf-8")
        except OSError:
            continue

        # Prefer the managed block, which the app writes.
        m = re.search(
            r"<!--\s*centurion:soul-structured:begin\s*-->.*?##\s*Name\s*\n+\s*(.+)",
            text,
            re.S | re.I,
        )
        if not m:
            m = re.search(r"^##\s*Name\s*\n+\s*(.+)$", text, re.M)
        if m:
            name = m.group(1).strip().splitlines()[0].strip()
            name = name.strip("*_` ")
            if name and name.lower() not in {"centurion", "your name", "name"}:
                return name[:60]
    return ""


def local_identity() -> dict[str, Any]:
    """This Brain's durable fleet identity, created on first call."""
    path = _identity_path()
    existing: dict[str, Any] = {}
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            existing = loaded
    except (OSError, json.JSONDecodeError):
        existing = {}

    name = soul_name() or existing.get("name") or os.uname().nodename or "Centurion"
    centurion_id = str(existing.get("centurion_id") or "")
    if not centurion_id:
        stem = _slug(str(name)) or "centurion"
        centurion_id = f"{stem}-{secrets.token_hex(3)}"

    record = {
        "centurion_id": centurion_id,
        "name": str(name),
        "created_at": existing.get("created_at") or time.time(),
        "updated_at": time.time(),
    }
    if record != existing:
        try:
            path.write_text(json.dumps(record, indent=2), encoding="utf-8")
        except OSError:
            # Not fatal: the identity still works for this session.
            pass
    return record


def local_centurion_id() -> str:
    return str(local_identity()["centurion_id"])


def local_display_name() -> str:
    return str(local_identity()["name"])


def fleet_token() -> str:
    """The shared fleet passphrase this Brain presents to peers.

    Must match what the receiver accepts: `CENTURION_FLEET_TOKEN` in .env, or
    the `fleet_token` in config.yaml (which the adapter cannot read, so the env
    var is the one that counts — see `fleet peer enable`).
    """
    tok = os.getenv("CENTURION_FLEET_TOKEN", "").strip()
    if tok:
        return tok
    try:
        from ruamel.yaml import YAML

        cfg = YAML().load((_home() / "config.yaml").read_text(encoding="utf-8"))
        extra = (
            ((cfg or {}).get("gateway") or {}).get("platforms") or {}
        ).get("api_server", {}).get("extra") or {}
        return str(extra.get("fleet_token") or "")
    except Exception:
        return ""


def build_transport():
    """A FleetTransport for this Brain, or None if it cannot be built.

    `FleetTransport` previously existed only in its own docstring and in tests —
    nothing in production ever constructed one, which is why the send path had
    never run.
    """
    try:
        from centurion.fleet.transport import FleetTransport
    except Exception:
        return None

    identity = local_identity()
    return FleetTransport(
        centurion_id=str(identity["centurion_id"]),
        centurion_name=str(identity["name"]),
        auth_token=fleet_token(),
    )
