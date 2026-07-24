"""JSON CLI for the Host Provider Control Plane (`centurion provider`)."""

from __future__ import annotations

import argparse
import json
import sys

from centurion_cli.provider_control import (
    apply_remote_switch,
    apply_switch,
    get_status,
    list_options,
    list_remote_options,
    restore_last_known_good,
    save_remote_api_key,
    validate_switch,
)


def _emit(payload: dict, *, as_json: bool) -> int:
    if as_json:
        sys.stdout.write(json.dumps(payload, ensure_ascii=False))
        sys.stdout.write("\n")
    else:
        if payload.get("ok"):
            sys.stdout.write("OK\n")
        else:
            sys.stderr.write(payload.get("message") or payload.get("error") or "Failed\n")
    return 0 if payload.get("ok") else 1


def provider_command(args: argparse.Namespace) -> None:
    sub = getattr(args, "provider_command", None)
    if sub == "status":
        code = _cmd_status(args)
    elif sub == "options":
        code = _cmd_options(args)
    elif sub == "catalog":
        code = _cmd_catalog(args)
    elif sub == "validate":
        code = _cmd_validate(args)
    elif sub == "set":
        code = _cmd_set(args)
    elif sub == "save-key":
        code = _cmd_save_key(args)
    elif sub == "apply-connector":
        code = _cmd_apply_connector(args)
    elif sub == "restore":
        code = _cmd_restore(args)
    else:
        print(
            "usage: centurion provider "
            "<status|options|catalog|validate|set|save-key|apply-connector|restore>",
            file=sys.stderr,
        )
        sys.exit(2)
        return
    sys.exit(int(code or 0))


def _cmd_status(args: argparse.Namespace) -> int:
    status = get_status(probe=not args.skip_probe)
    payload = {"ok": True, "status": status.to_dict()}
    return _emit(payload, as_json=args.json)


def _cmd_options(args: argparse.Namespace) -> int:
    options = list_options(max_models=args.max_models)
    payload = {"ok": True, "options": options}
    return _emit(payload, as_json=args.json)


def _cmd_catalog(args: argparse.Namespace) -> int:
    catalog = list_remote_options(probe=bool(getattr(args, "probe", False)))
    payload = {"ok": True, "catalog": catalog}
    return _emit(payload, as_json=args.json)


def _cmd_validate(args: argparse.Namespace) -> int:
    result = validate_switch(args.provider, args.model, probe=not args.skip_probe)
    payload = {"ok": result.ok, "result": result.to_dict()}
    if not result.ok:
        payload["message"] = result.message
        payload["code"] = result.code
    return _emit(payload, as_json=args.json)


def _cmd_set(args: argparse.Namespace) -> int:
    result = apply_switch(args.provider, args.model, probe=not args.skip_probe)
    payload = {"ok": result.ok, "result": result.to_dict()}
    if not result.ok:
        payload["message"] = result.message
        payload["code"] = result.code
    return _emit(payload, as_json=args.json)


def _cmd_save_key(args: argparse.Namespace) -> int:
    key = args.key
    if key == "-":
        key = sys.stdin.read()
    result = save_remote_api_key(args.connector_id, key)
    # Never echo the access code back in the payload.
    payload = {
        "ok": bool(result.get("ok")),
        "connector_id": result.get("connector_id"),
        "configured": result.get("configured"),
        "message": result.get("message"),
    }
    return _emit(payload, as_json=args.json)


def _cmd_apply_connector(args: argparse.Namespace) -> int:
    result = apply_remote_switch(args.connector_id, probe=not args.skip_probe)
    payload = {"ok": result.ok, "result": result.to_dict()}
    if not result.ok:
        payload["message"] = result.message
        payload["code"] = result.code
    return _emit(payload, as_json=args.json)


def _cmd_restore(args: argparse.Namespace) -> int:
    result = restore_last_known_good(probe=not args.skip_probe)
    payload = {"ok": result.ok, "result": result.to_dict()}
    if not result.ok:
        payload["message"] = result.message
        payload["code"] = result.code
    return _emit(payload, as_json=args.json)


def register_subparser(subparsers) -> None:
    provider_parser = subparsers.add_parser(
        "provider",
        help="Manage thinking-service provider/model configuration (JSON API)",
        description="Host Provider Control Plane — status, catalog, save-key, apply-connector, set, restore.",
    )
    provider_parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON",
    )
    provider_sub = provider_parser.add_subparsers(dest="provider_command", required=True)

    status_parser = provider_sub.add_parser("status", help="Current provider health")
    status_parser.add_argument(
        "--skip-probe",
        action="store_true",
        help="Skip live connectivity probe",
    )
    status_parser.set_defaults(func=provider_command)

    options_parser = provider_sub.add_parser("options", help="Curated provider/model list")
    options_parser.add_argument("--max-models", type=int, default=50)
    options_parser.set_defaults(func=provider_command)

    catalog_parser = provider_sub.add_parser(
        "catalog",
        help="Remote BYOK catalog (text + creative connectors)",
    )
    catalog_parser.add_argument(
        "--probe",
        action="store_true",
        help="Live-probe configured text connectors (slower)",
    )
    catalog_parser.set_defaults(func=provider_command)

    validate_parser = provider_sub.add_parser(
        "validate",
        help="Dry-run provider switch with optional probe",
    )
    validate_parser.add_argument("provider")
    validate_parser.add_argument("model")
    validate_parser.add_argument("--skip-probe", action="store_true")
    validate_parser.set_defaults(func=provider_command)

    set_parser = provider_sub.add_parser("set", help="Apply provider switch")
    set_parser.add_argument("provider")
    set_parser.add_argument("model")
    set_parser.add_argument("--skip-probe", action="store_true")
    set_parser.set_defaults(func=provider_command)

    save_key_parser = provider_sub.add_parser(
        "save-key",
        help="Save an access code for a curated connector on this brain",
    )
    save_key_parser.add_argument("connector_id")
    save_key_parser.add_argument(
        "key",
        help="Access code, or '-' to read from stdin (never echoed in JSON output)",
    )
    save_key_parser.set_defaults(func=provider_command)

    apply_connector_parser = provider_sub.add_parser(
        "apply-connector",
        help="Apply a curated remote catalog connector",
    )
    apply_connector_parser.add_argument("connector_id")
    apply_connector_parser.add_argument("--skip-probe", action="store_true")
    apply_connector_parser.set_defaults(func=provider_command)

    restore_parser = provider_sub.add_parser(
        "restore",
        help="Restore last known good provider/model",
    )
    restore_parser.add_argument("--skip-probe", action="store_true")
    restore_parser.set_defaults(func=provider_command)

    provider_parser.set_defaults(func=provider_command)
