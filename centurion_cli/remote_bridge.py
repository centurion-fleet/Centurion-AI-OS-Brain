"""Local stdio bridge from the native Linux remote service to Centurion.

The bridge deliberately has no network listener. ``centurion-remote`` owns the
encrypted LAN boundary and invokes this module with a JSON request on stdin.
Keeping the Python process behind stdio prevents the full dashboard/admin API
from being exposed to the local network.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable
from typing import Any


def handle_request(
    request: dict[str, Any],
    *,
    run_agent: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    """Run one native-remote chat request and return a JSON-safe response."""
    request_id = str(request.get("id") or "")
    text = request.get("text")
    if not isinstance(text, str) or not text.strip():
        return {
            "id": request_id,
            "ok": False,
            "error": "Message text is required.",
        }

    if run_agent is None:
        run_agent = _run_agent_quiet

    try:
        response = run_agent(text.strip())
    except Exception as exc:
        return {
            "id": request_id,
            "ok": False,
            "error": f"Your Centurion could not respond: {exc}",
        }

    return {
        "id": request_id,
        "ok": True,
        "text": response or "",
    }


def _run_agent_quiet(text: str) -> str:
    """Run one agent turn without polluting stdout (bridge response must be pure JSON)."""
    import logging
    import os
    from contextlib import redirect_stderr, redirect_stdout

    from centurion_cli.oneshot import _run_agent

    logging.disable(logging.CRITICAL)
    os.environ.setdefault("CENTURION_YOLO_MODE", "1")
    os.environ.setdefault("CENTURION_ACCEPT_HOOKS", "1")
    with open(os.devnull, "w", encoding="utf-8") as devnull, redirect_stdout(
        devnull
    ), redirect_stderr(devnull):
        return _run_agent(text) or ""


def _read_request() -> dict[str, Any]:
    raw = sys.stdin.read()
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("request must be a JSON object")
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Local bridge used by the native Centurion remote service."
    )
    parser.parse_args(argv)

    try:
        request = _read_request()
        response = handle_request(request)
    except Exception as exc:
        response = {"id": "", "ok": False, "error": str(exc)}

    sys.stdout.write(json.dumps(response, ensure_ascii=False))
    sys.stdout.write("\n")
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
