"""CLI subcommand: ``centurion telegram import``."""

from __future__ import annotations

import argparse
import json
import sys


def register_cli(parser: argparse.ArgumentParser) -> None:
    subparsers = parser.add_subparsers(dest="telegram_command", required=True)

    import_parser = subparsers.add_parser(
        "import",
        help="Export the Centurion Telegram bot DM for Centurion Remote import",
    )
    import_parser.add_argument(
        "--for-remote",
        action="store_true",
        help="Build an import bundle for Centurion Remote",
    )
    import_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview the export without writing files",
    )
    import_parser.add_argument(
        "--session-id",
        default="",
        help="Specific Telegram session id to export",
    )
    import_parser.set_defaults(func=_cmd_import)


def _cmd_import(args) -> int:
    from centurion_cli.telegram_import import build_import_bundle

    bundle = build_import_bundle(
        session_id=(args.session_id or None),
        dry_run=bool(args.dry_run),
    )
    if not bundle.get("ok"):
        print(bundle.get("message") or "Telegram import failed.", file=sys.stderr)
        return 1
    if args.for_remote or args.dry_run:
        print(json.dumps(bundle, indent=2))
        return 0
    print(f"Import bundle written to {bundle.get('manifest_path') or bundle.get('bundle_path')}")
    return 0
