"""``centurion license`` — product license status, activate, redeem, reissue.

Subcommands:
  status            Show entitlement + enforcement mode
  activate          Start trial or activate subscription
  redeem            (retired) proof-of-purchase token — no outright licences
  fingerprint       Print this machine's license fingerprint
  reissue-request   Request hardware re-bind after machine failure
  checkin           Force a phone-home check-in now
  unbox             DIF Y first-boot welcome (pre-seeded licenses)
"""

from __future__ import annotations

import argparse
import sys
from typing import Optional

from centurion_cli.colors import Colors, color
from centurion_cli.config import load_config


def _cfg():
    return load_config() or {}


def _cmd_status(_args) -> int:
    from centurion.license.edition import current_edition
    from centurion.license.enforcement import evaluate, locked_user_message
    from centurion.license.fingerprint import fingerprint_short
    from centurion.license.phone_home import is_phone_home_due
    from centurion.license.store import load_entitlement

    config = _cfg()
    ent = load_entitlement()
    decision = evaluate(ent, config=config)
    edition = current_edition()

    print()
    print(color("  Centurion License", Colors.MAGENTA))
    print(color("  ─────────────────", Colors.MAGENTA))
    print(f"  State:        {ent.state}")
    print(f"  Edition:      {edition.label}")
    print(f"  Seats:        {edition.seat_limit}")
    print(
        f"  Instrument:   {'live' if edition.instrument_unlocked else 'greyed (Accountant edition)'}"
    )
    print(f"  Tier:         {ent.tier or '—'}")
    print(f"  License ID:   {ent.license_id or '—'}")
    print(f"  Fingerprint:  {fingerprint_short(ent.machine_fingerprint)}")
    if not edition.fingerprint_matches:
        print(
            color(
                "  Binding:      this entitlement is bound to another machine",
                Colors.YELLOW,
            )
        )
    if edition.tampered:
        print(color(f"  Edition held: {edition.note}", Colors.YELLOW))
    if ent.customer_name:
        print(f"  Customer:     {ent.customer_name}")
    if ent.shipment_id:
        print(f"  Shipment:     {ent.shipment_id}")
    print(f"  Enforcement:  {decision.mode.value}")
    if ent.last_verified_at:
        from datetime import datetime, timezone

        verified = datetime.fromtimestamp(ent.last_verified_at, tz=timezone.utc)
        print(f"  Last check:   {verified.strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"  Phone-home:   {'due' if is_phone_home_due(ent, config=config) else 'not due'}")
    msg = locked_user_message(decision)
    if msg:
        print()
        print(f"  {msg}")
    print()
    return 0


def _cmd_activate(args) -> int:
    from centurion.license.activate import activate_from_server, activate_trial

    config = _cfg()
    tier = (getattr(args, "tier", None) or "trial").strip().lower()
    if tier == "trial":
        result = activate_trial(
            days=int(getattr(args, "days", 14) or 14),
            config=config,
            offline=bool(getattr(args, "offline", False)),
        )
    else:
        result = activate_from_server(
            tier=tier,
            activation_code=getattr(args, "code", None),
            api_key=getattr(args, "api_key", None),
            config=config,
        )
    if not result.ok:
        print(f"Activation failed: {result.error}", file=sys.stderr)
        return 1
    print(result.message or "Activated")
    return 0


def _cmd_redeem(args) -> int:
    from centurion.license.activate import redeem_purchase_token

    token = (getattr(args, "token", None) or "").strip()
    if not token:
        print("Usage: centurion license redeem <token>", file=sys.stderr)
        return 1
    result = redeem_purchase_token(
        token,
        config=_cfg(),
    )
    if not result.ok:
        print(f"Redeem failed: {result.error}", file=sys.stderr)
        return 1
    print(result.message or "Redeemed")
    return 0


def _cmd_fingerprint(_args) -> int:
    from centurion.license.fingerprint import collect_identity_parts, compute_fingerprint

    parts = collect_identity_parts()
    fp = compute_fingerprint(parts=parts)
    print(fp)
    if getattr(_args, "verbose", False):
        for key in sorted(parts.keys()):
            value = parts[key]
            # Redact long machine ids in verbose display slightly
            display = value if len(value) < 48 else value[:20] + "…" + value[-8:]
            print(f"  {key}: {display}")
    return 0


def _cmd_reissue(args) -> int:
    from centurion.license.activate import request_reissue

    reason = (getattr(args, "reason", None) or "hardware_failure").strip()
    result = request_reissue(
        reason=reason,
        proof_of_purchase=getattr(args, "proof", None),
        old_fingerprint=getattr(args, "old_fingerprint", None),
        config=_cfg(),
    )
    if not result.ok:
        print(f"Reissue failed: {result.error}", file=sys.stderr)
        return 1
    print(result.message or "Reissue requested")
    return 0


def _cmd_checkin(_args) -> int:
    from centurion.license.phone_home import phone_home

    result = phone_home(config=_cfg(), force=True)
    if result.network_error:
        print(f"Network error (grace continues): {result.error}", file=sys.stderr)
        return 2
    if not result.ok:
        print(f"Check-in failed: {result.error}", file=sys.stderr)
        return 1
    print(f"Check-in ok — state={result.state or 'unchanged'}")
    return 0


def _cmd_unbox(_args) -> int:
    """DIF Y first-boot welcome for pre-seeded machines."""
    from centurion.license.enforcement import evaluate
    from centurion.license.fingerprint import fingerprint_short
    from centurion.license.store import load_entitlement

    ent = load_entitlement()
    decision = evaluate(ent, config=_cfg())
    print()
    print(color("  Welcome to your Centurion Sovereign", Colors.MAGENTA))
    print(color("  ──────────────────────────────────", Colors.MAGENTA))
    if ent.customer_name:
        print(f"  Licensed to:  {ent.customer_name}")
    print(f"  Tier:         {ent.tier or ent.state}")
    print(f"  State:        {ent.state}")
    print(f"  Fingerprint:  {fingerprint_short(ent.machine_fingerprint)}")
    if ent.shipment_id:
        print(f"  Shipment:     {ent.shipment_id}")
    print()
    if decision.mode.value == "locked" and ent.state == "unactivated":
        print("  This machine is not licensed yet.")
        print("  Run: centurion license activate trial")
    else:
        print("  Your license is ready. Optional next steps:")
        print("    centurion setup          # providers / SOUL")
        print("    centurion gateway setup  # messaging")
        print("    Pair Centurion Remote from the Desktop app")
    print()
    return 0


def license_command(args) -> int:
    sub = getattr(args, "license_command", None) or "status"
    handlers = {
        "status": _cmd_status,
        "activate": _cmd_activate,
        "redeem": _cmd_redeem,
        "fingerprint": _cmd_fingerprint,
        "reissue-request": _cmd_reissue,
        "checkin": _cmd_checkin,
        "unbox": _cmd_unbox,
    }
    handler = handlers.get(sub)
    if handler is None:
        print(f"Unknown license subcommand: {sub}", file=sys.stderr)
        print("Run `centurion license -h` for usage.", file=sys.stderr)
        return 1
    return handler(args)


def add_parser(subparsers) -> None:
    """Register `centurion license` on the given argparse subparsers object."""
    parser = subparsers.add_parser(
        "license",
        help="Product license status, activation, and phone-home",
        description=(
            "Manage Centurion product licensing (monthly subscription). "
            "Subcommands: status, activate, redeem, fingerprint, "
            "reissue-request, checkin, unbox."
        ),
    )
    sub = parser.add_subparsers(dest="license_command")

    sub.add_parser("status", help="Show entitlement and enforcement status (default)")

    activate = sub.add_parser("activate", help="Activate trial / subscription")
    activate.add_argument(
        "tier",
        nargs="?",
        default="trial",
        help="trial | subscription",
    )
    activate.add_argument("--code", help="Activation / checkout code from the portal")
    activate.add_argument("--api-key", help="API key associated with the subscription")
    activate.add_argument("--days", type=int, default=14, help="Trial length in days")
    activate.add_argument(
        "--offline",
        action="store_true",
        help="Start a local trial without contacting the license server",
    )

    redeem = sub.add_parser(
        "redeem",
        help="(retired) proof-of-purchase token — outright licences no longer exist",
    )
    redeem.add_argument("token", nargs="?", help="Proof-of-purchase token")

    fp = sub.add_parser("fingerprint", help="Print this machine's license fingerprint")
    fp.add_argument("-v", "--verbose", action="store_true", help="Show identity components")

    reissue = sub.add_parser(
        "reissue-request",
        help="Request license re-bind after hardware failure",
    )
    reissue.add_argument("--reason", default="hardware_failure")
    reissue.add_argument("--proof", help="Proof-of-purchase reference")
    reissue.add_argument("--old-fingerprint", dest="old_fingerprint")

    sub.add_parser("checkin", help="Force a license phone-home check-in now")
    sub.add_parser("unbox", help="DIF Y first-boot welcome for pre-seeded machines")

    parser.set_defaults(func=license_command)
