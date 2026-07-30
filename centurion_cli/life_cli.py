"""CLI: ``centurion life import-docs`` — recover filesystem / plans into Focus docs."""

from __future__ import annotations

import argparse
import json


def _cmd_import_docs(args: argparse.Namespace) -> int:
    from centurion_cli.life_missions import import_scanned_documents

    roots = list(args.path) if args.path else None
    result = import_scanned_documents(
        roots=roots,
        mission_id=args.mission_id or None,
        include_plans=not args.no_plans,
        include_outcomes=not args.no_outcomes,
        max_files=int(args.max_files or 2000),
    )
    if args.json:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(
            f"Imported {result['imported']} · updated {result['updated']} · "
            f"skipped {result['skipped']} · scanned files {result['scanned_files']}"
        )
        if result.get("roots"):
            print("Roots:")
            for root in result["roots"]:
                print(f"  {root}")
        errors = result.get("errors") or []
        if errors:
            print(f"Errors ({len(errors)} shown):")
            for err in errors:
                print(f"  {err}")
    return 0


def register_cli(parent: argparse.ArgumentParser) -> None:
    parent.set_defaults(func=lambda a: (parent.print_help(), 0)[1])
    sub = parent.add_subparsers(dest="life_command")
    imp = sub.add_parser(
        "import-docs",
        help="Scan this machine and import text docs / plans into Focus documents",
        description=(
            "Walks Documents/Desktop (and optional --path roots), plus Home plans "
            "and kanban outcomes, into life_documents so Focus Find documents can "
            "search early write-ups."
        ),
    )
    imp.add_argument(
        "--path",
        action="append",
        default=[],
        help="Extra directory to scan (repeatable). Default: Documents, Desktop, ~/centurion, /home/Legio/centurion, terminal.cwd",
    )
    imp.add_argument(
        "--mission-id",
        default="",
        help="Attach imports to this mission when path/title match is weak",
    )
    imp.add_argument(
        "--no-plans",
        action="store_true",
        help="Skip importing {CENTURION_HOME}/plans JSON",
    )
    imp.add_argument(
        "--no-outcomes",
        action="store_true",
        help="Skip importing kanban/swarm task outcomes",
    )
    imp.add_argument(
        "--max-files",
        type=int,
        default=2000,
        help="Cap on filesystem files to import (default 2000)",
    )
    imp.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable JSON",
    )
    imp.set_defaults(func=_cmd_import_docs)
