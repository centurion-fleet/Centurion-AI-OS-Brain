"""CLI subcommand: ``centurion telegram import``.

One-time transition for early Centurions that started on the Telegram bot —
brings that bot DM history into a bundle on the Linux brain. Not a product
feature for new customers; lives on the host, not on CenturionAI Remote.
"""

from __future__ import annotations

import argparse
import json
import sys


def register_cli(parser: argparse.ArgumentParser) -> None:
    subparsers = parser.add_subparsers(dest="telegram_command", required=True)

    import_parser = subparsers.add_parser(
        "import",
        help=(
            "One-time: bring over Telegram bot DM history for early Centurions "
            "(host-side transition; not for CenturionAI Remote)"
        ),
    )
    import_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview without writing files",
    )
    import_parser.add_argument(
        "--session-id",
        default="",
        help="Specific Telegram session id to export",
    )
    import_parser.add_argument(
        "--json",
        action="store_true",
        help="Print a JSON summary (for desktop Settings)",
    )
    import_parser.add_argument(
        "--for-remote",
        action="store_true",
        help=argparse.SUPPRESS,  # legacy full-bundle dump
    )
    import_parser.set_defaults(func=_cmd_import)


def _summary_payload(bundle: dict) -> dict:
    """Compact shape for GTK Settings / operators — never dump full history."""
    return {
        "ok": bool(bundle.get("ok")),
        "message": bundle.get("message"),
        "message_count": int(bundle.get("message_count") or 0),
        "file_count": int(bundle.get("file_count") or 0),
        "missing_file_count": int(bundle.get("missing_file_count") or 0),
        "session_id": bundle.get("session_id"),
        "manifest_path": bundle.get("manifest_path") or "",
        "bundle_path": bundle.get("bundle_path") or "",
        "candidate_count": len(bundle.get("candidates") or []),
    }


def _cmd_import(args) -> int:
    from centurion_cli.telegram_import import build_import_bundle

    bundle = build_import_bundle(
        session_id=(args.session_id or None),
        dry_run=bool(args.dry_run),
    )
    ok = bool(bundle.get("ok"))

    if args.for_remote:
        print(json.dumps(bundle, indent=2))
        return 0 if ok else 1

    if args.json:
        print(json.dumps(_summary_payload(bundle), indent=2))
        return 0 if ok else 1

    if not ok:
        print(bundle.get("message") or "Telegram history bring-over failed.", file=sys.stderr)
        return 1

    if args.dry_run:
        print(
            f"Found Telegram bot history: {bundle.get('message_count', 0)} messages, "
            f"{bundle.get('file_count', 0)} files "
            f"({bundle.get('missing_file_count', 0)} attachments missing)."
        )
        return 0

    print(
        "Telegram history saved on this Centurion "
        f"({bundle.get('message_count', 0)} messages) → "
        f"{bundle.get('manifest_path') or bundle.get('bundle_path')}"
    )
    return 0
