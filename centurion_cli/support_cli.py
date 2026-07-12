"""JSON CLI for structured support bundles (`centurion support`)."""

from __future__ import annotations

import argparse
import json
import sys

from centurion_cli.support_control import (
    auto_fix_thinking,
    collect_health_snapshot,
    create_support_bundle,
    format_bundle_for_display,
    list_backup_thinking_services,
    lookup_support_bundle,
)


def _emit(payload: dict, *, as_json: bool) -> int:
    if as_json:
        sys.stdout.write(json.dumps(payload, ensure_ascii=False))
        sys.stdout.write("\n")
    else:
        if payload.get("ok"):
            if payload.get("code"):
                sys.stdout.write(f"Support code: {payload['code']}\n")
            elif payload.get("summary"):
                sys.stdout.write(f"{payload['summary']}\n")
            else:
                sys.stdout.write("OK\n")
        else:
            sys.stderr.write(payload.get("message") or payload.get("error") or "Failed\n")
    return 0 if payload.get("ok") else 1


def support_command(args: argparse.Namespace) -> None:
    sub = getattr(args, "support_command", None)
    if sub == "health":
        code = _cmd_health(args)
    elif sub == "bundle":
        code = _cmd_bundle(args)
    elif sub == "show":
        code = _cmd_show(args)
    elif sub == "auto-fix":
        code = _cmd_auto_fix(args)
    elif sub == "backups":
        code = _cmd_backups(args)
    else:
        print(
            "usage: centurion support <health|bundle|show|auto-fix|backups>",
            file=sys.stderr,
        )
        sys.exit(2)
        return
    sys.exit(int(code or 0))


def _cmd_health(args: argparse.Namespace) -> int:
    snapshot = collect_health_snapshot(probe=not args.skip_probe)
    payload = {
        "ok": True,
        "snapshot": snapshot.to_dict(),
        "summary": snapshot.thinking_message,
        "thinking_health": snapshot.thinking_health,
        "message": snapshot.thinking_message,
    }
    return _emit(payload, as_json=args.json)


def _cmd_bundle(args: argparse.Namespace) -> int:
    result = create_support_bundle(probe=not args.skip_probe)
    payload = result.to_dict()
    payload["ok"] = result.ok
    return _emit(payload, as_json=args.json)


def _cmd_show(args: argparse.Namespace) -> int:
    bundle = lookup_support_bundle(args.code)
    if bundle is None:
        payload = {
            "ok": False,
            "message": f"Support code not found or expired: {args.code}",
        }
        return _emit(payload, as_json=args.json)
    payload = {
        "ok": True,
        "result": bundle,
        "message": format_bundle_for_display(bundle),
    }
    return _emit(payload, as_json=args.json)


def _cmd_backups(args: argparse.Namespace) -> int:
    backups = list_backup_thinking_services()
    payload = {
        "ok": True,
        "result": {"backups": backups, "count": len(backups)},
        "message": f"{len(backups)} backup thinking service(s) configured.",
    }
    return _emit(payload, as_json=args.json)


def _cmd_auto_fix(args: argparse.Namespace) -> int:
    result = auto_fix_thinking(probe=not args.skip_probe)
    payload = result.to_dict()
    payload["ok"] = result.ok
    return _emit(payload, as_json=args.json)


def register_subparser(subparsers) -> None:
    support_parser = subparsers.add_parser(
        "support",
        help="Structured support health checks and bundles (JSON API)",
        description="Support plane — health snapshot, support codes, lookup, auto-fix.",
    )
    support_parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON",
    )
    support_sub = support_parser.add_subparsers(dest="support_command", required=True)

    health_parser = support_sub.add_parser("health", help="Collect health snapshot")
    health_parser.add_argument("--skip-probe", action="store_true")
    health_parser.set_defaults(func=support_command)

    bundle_parser = support_sub.add_parser("bundle", help="Generate a support code")
    bundle_parser.add_argument("--skip-probe", action="store_true")
    bundle_parser.set_defaults(func=support_command)

    show_parser = support_sub.add_parser("show", help="Look up a support code")
    show_parser.add_argument("code")
    show_parser.set_defaults(func=support_command)

    auto_fix_parser = support_sub.add_parser(
        "auto-fix",
        help="Restore last working setup and re-probe",
    )
    auto_fix_parser.add_argument("--skip-probe", action="store_true")
    auto_fix_parser.set_defaults(func=support_command)

    backups_parser = support_sub.add_parser(
        "backups",
        help="List configured backup thinking services (read-only)",
    )
    backups_parser.set_defaults(func=support_command)

    support_parser.set_defaults(func=support_command)
