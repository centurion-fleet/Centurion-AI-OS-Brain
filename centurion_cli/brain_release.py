"""Release-channel update check for a packaged Sovereign AI Brain.

A Brain installed from a Get Brain download (the RPM) has no git checkout and
is not a pip install, so the pip/PyPI check can never answer for it. It used to
fall through to the pip path anyway, which meant every customer's Brain quietly
asked PyPI about a Python package, failed, reported `status: "unavailable"`, and
told the customer to open a Terminal:

    Could not reach PyPI to check for updates.
      Use: uv pip install --upgrade 'centurionai-os'

The app only lights its update badge on `update_available` or `up_to_date`, so
that failure was invisible — no badge, no message, nothing.

This module asks the release channel we actually publish to, which already
serves the current artefact for the installer row.
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request

# The master public URL. personalcenturion.com also serves this and 307s here.
# Overridable for testing without touching the real channel.
RELEASE_API = os.environ.get(
    "CENTURION_RELEASE_API",
    "https://www.1human1ai.com/api/v1/releases/latest",
)

DEFAULT_TIMEOUT = 8.0

# Statuses the desktop app understands.
STATUS_UP_TO_DATE = "up_to_date"
STATUS_UPDATE_AVAILABLE = "update_available"
STATUS_UNAVAILABLE = "unavailable"


def _version_key(value: str) -> tuple[int, ...]:
    """Turn '6.0.7' into (6, 0, 7) so versions compare numerically.

    Non-numeric suffixes are dropped rather than raised on — a malformed
    version must not make the update check throw.
    """
    parts: list[int] = []
    for chunk in re.split(r"[._\-+]", value.strip()):
        m = re.match(r"^(\d+)", chunk)
        if m:
            parts.append(int(m.group(1)))
        else:
            break
    return tuple(parts) or (0,)


def fetch_latest_release(timeout: float = DEFAULT_TIMEOUT) -> dict | None:
    """Return the published release, or None if the channel cannot be reached."""
    req = urllib.request.Request(
        RELEASE_API,
        headers={"Accept": "application/json", "User-Agent": "centurion-brain-update-check"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
        payload = json.loads(raw.decode("utf-8", errors="replace"))
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return None

    if not isinstance(payload, dict):
        return None
    release = payload.get("release")
    if not isinstance(release, dict) or not release.get("version"):
        return None
    return release


def check_brain_release(current_version: str) -> dict:
    """Compare the installed Brain against the published release.

    Returns a dict with `status`, `latest_version` and `message`, shaped so the
    caller can merge it straight into the update-check payload.
    """
    release = fetch_latest_release()
    if release is None:
        return {
            "status": STATUS_UNAVAILABLE,
            "latest_version": None,
            "message": "Could not reach the Centurion release channel to check for updates.",
        }

    latest = str(release["version"]).strip()
    if _version_key(latest) > _version_key(current_version):
        return {
            "status": STATUS_UPDATE_AVAILABLE,
            "latest_version": latest,
            "message": f"Sovereign AI Brain {latest} is available.",
            "title": release.get("title"),
            "sha256": release.get("sha256"),
        }
    return {
        "status": STATUS_UP_TO_DATE,
        "latest_version": latest,
        "message": "Already up to date.",
    }
