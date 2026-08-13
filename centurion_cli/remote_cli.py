"""
CLI wrapper for centurion-remote pairing tokens.

Usage:
    centurion remote pair [--host HOST] [--label LABEL] [--json]
                          [--qr | --no-qr] [--qr-png PATH] [--include-qr]
    centurion remote tokens [--json]
    centurion remote revoke <id>
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


def _centurion_remote_bin() -> str:
    home = Path.home()
    candidate = home / ".local" / "bin" / "centurion-remote"
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    found = shutil.which("centurion-remote")
    if found:
        return found
    return "centurion-remote"


def _run_remote(argv: list[str]) -> int:
    cmd = [_centurion_remote_bin(), *argv]
    try:
        result = subprocess.run(cmd, check=False)
    except FileNotFoundError:
        print(
            "centurion-remote was not found. Install the desktop-native package "
            "(see brain/linux/README.md) or put centurion-remote on PATH.",
            file=sys.stderr,
        )
        return 1
    return int(result.returncode)


def remote_command(args) -> int:
    """Handle ``centurion remote`` subcommands."""
    action = getattr(args, "remote_action", None)
    if action == "pair":
        argv = ["remote-pair"]
        label = getattr(args, "label", None) or "iPhone"
        argv.extend(["--label", label])
        host = getattr(args, "host", None)
        if host:
            argv.extend(["--host", host])
        if getattr(args, "json", False):
            argv.append("--json")
        if getattr(args, "qr", False):
            argv.append("--qr")
        if getattr(args, "no_qr", False):
            argv.append("--no-qr")
        qr_png = getattr(args, "qr_png", None)
        if qr_png:
            argv.extend(["--qr-png", str(qr_png)])
        if getattr(args, "include_qr", False):
            argv.append("--include-qr")
        return _run_remote(argv)
    if action == "tokens":
        argv = ["remote-tokens"]
        if getattr(args, "json", False):
            argv.append("--json")
        return _run_remote(argv)
    if action == "revoke":
        token_id = getattr(args, "token_id", None)
        if not token_id:
            print("Usage: centurion remote revoke <id>", file=sys.stderr)
            return 2
        return _run_remote(["remote-revoke", token_id])

    print("Usage: centurion remote {pair|tokens|revoke}")
    print("Run 'centurion remote --help' for details.")
    return 2


def format_connection_string(secret: str, host: str, port: int = 9119) -> str:
    """Pure helper for tests / callers that already have a secret."""
    return f"token:{secret}@{host}:{port}"


def parse_connection_string(value: str) -> tuple[str, str, int] | None:
    """Parse ``token:<secret>@<host>:<port>`` (port optional)."""
    trimmed = value.strip()
    if not trimmed.startswith("token:"):
        return None
    rest = trimmed[len("token:") :]
    if "@" not in rest:
        return None
    secret, hostport = rest.split("@", 1)
    if not secret or not hostport:
        return None
    if ":" in hostport:
        # Split on last colon so IPv6-ish hosts without brackets still fail safely.
        host, _, port_str = hostport.rpartition(":")
        if host and port_str.isdigit():
            return secret, host, int(port_str)
    return secret, hostport, 9119
