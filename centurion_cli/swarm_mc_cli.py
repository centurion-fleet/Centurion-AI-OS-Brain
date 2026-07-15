"""``centurion swarm connect`` and ``centurion swarm link`` — Mission Control token management."""
from __future__ import annotations

import argparse
import json
import os
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from centurion_cli.colors import Colors, color
from centurion_cli.config import load_config, save_config
from gateway.swarm_mc import DEFAULT_PORTAL_API, save_mc_config


def cmd_swarm_link(args: argparse.Namespace) -> int:
    """``centurion swarm link`` — link an instance token (ctk_inst_*) to your customer account."""
    token = (getattr(args, "token", None) or os.getenv("CTK_INSTANCE_TOKEN", "")).strip()
    api_base = (getattr(args, "portal_url", None) or os.getenv("CENTURION_PORTAL_API", DEFAULT_PORTAL_API)).rstrip("/")

    if not token.startswith("ctk_inst_"):
        print(
            color("Provide --token ctk_inst_... from Mission Control setup.", Colors.YELLOW),
            file=sys.stderr,
        )
        return 1

    # Primary token: --primary-token > env var > auth.json
    primary_token = (getattr(args, "primary_token", None) or os.getenv("CTK_PRIMARY_TOKEN", "")).strip()
    if not primary_token:
        auth_path = os.path.join(
            os.environ.get("CENTURION_HOME", os.path.expanduser("~/.centurion")),
            "auth.json",
        )
        if os.path.isfile(auth_path):
            try:
                with open(auth_path, encoding="utf-8") as f:
                    auth = json.load(f)
                pool = auth.get("credential_pool", {})
                nous = pool.get("nous", [])
                if nous:
                    primary_token = nous[0].get("access_token", "")
            except Exception:
                pass

    if not primary_token:
        print(
            color(
                "No primary token found. Run: centurion auth add nous --type api-key --api-key <your_ctk_primary>",
                Colors.YELLOW,
            ),
            file=sys.stderr,
        )
        return 1

    print(color(f"  Linking instance {token[:18]}...", Colors.CYAN))

    req = Request(
        f"{api_base}/api/v1/swarm/link",
        data=json.dumps({"instance_token": token}).encode(),
        headers={
            "Authorization": f"Bearer {primary_token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode())
    except HTTPError as e:
        detail = e.read().decode()[:300]
        print(color(f"  Link failed ({e.code}): {detail}", Colors.RED), file=sys.stderr)
        return 1

    # The API returns customer_id on success (not project_token + install_id)
    customer_id = result.get("customer_id", "")
    if customer_id:
        print()
        print(color("  Instance linked \u2713", Colors.GREEN))
        print(f"  Customer ID: {customer_id}")
        print()
        print(color("  The instance is now linked to your customer account.", Colors.GREEN))
        print("  To connect to a project, run:")
        print(color("    centurion swarm connect --token <ctk_proj_...> --project-id <id> --install-id <id>", Colors.CYAN))
        return 0

    # Fallback: if the API returns project_token + install_id (legacy), auto-connect
    project_token = result.get("project_token", "")
    project_id = result.get("project_id", "")
    install_id = result.get("install_id", "")
    if project_token and project_id and install_id:
        save_mc_config(project_id, project_token, install_id)
        config = load_config() or {}
        platforms = config.setdefault("platforms", {})
        mc = platforms.setdefault("swarm_mc", {})
        if isinstance(mc, dict):
            mc["enabled"] = True
            mc["project_id"] = project_id
            mc["install_id"] = install_id
        save_config(config)
        os.environ["CTK_PROJECT_TOKEN"] = project_token
        os.environ["CENTURION_INSTALL_ID"] = install_id
        print()
        print(color("  Instance linked \u2713", Colors.GREEN))
        print(f"  Project:       {project_id}")
        print(f"  Install:       {install_id}")
        print(f"  Project token: {project_token[:22]}...")
        print()
        print(color("  Mission Control connected. Use mission_control_* tools via the gateway.", Colors.GREEN))
        return 0

    print(
        color(f"  Unexpected response: {json.dumps(result)[:300]}", Colors.RED),
        file=sys.stderr,
    )
    return 1


def cmd_swarm_connect(args: argparse.Namespace) -> int:
    token = (getattr(args, "token", None) or os.getenv("CTK_PROJECT_TOKEN", "")).strip()
    install_id = (getattr(args, "install_id", None) or os.getenv("CENTURION_INSTALL_ID", "")).strip()
    project_id = (getattr(args, "project_id", None) or "").strip()

    if not token.startswith("ctk_proj_"):
        print(
            color("Provide --token ctk_proj_... from Mission Control setup or invite accept.", Colors.YELLOW),
            file=sys.stderr,
        )
        return 1
    if not install_id:
        print(color("Provide --install-id (fleet checkin install_id).", Colors.YELLOW), file=sys.stderr)
        return 1
    if not project_id:
        print(color("Provide --project-id (swarm project UUID).", Colors.YELLOW), file=sys.stderr)
        return 1

    save_mc_config(project_id, token, install_id)

    config = load_config() or {}
    platforms = config.setdefault("platforms", {})
    mc = platforms.setdefault("swarm_mc", {})
    if isinstance(mc, dict):
        mc["enabled"] = True
        mc["project_id"] = project_id
        mc["install_id"] = install_id
    save_config(config)

    os.environ["CTK_PROJECT_TOKEN"] = token
    os.environ["CENTURION_INSTALL_ID"] = install_id

    print()
    print(color("  Mission Control connected", Colors.GREEN))
    print(f"  Project:   {project_id}")
    print(f"  Install:   {install_id}")
    print(f"  Token:     {token[:22]}...")
    print()
    print("  Titus can use mission_control_* tools when the gateway is running.")
    return 0


def swarm_command(args: argparse.Namespace) -> int:
    sub = getattr(args, "swarm_action", None)
    if sub == "link":
        return cmd_swarm_link(args)
    if sub == "connect":
        return cmd_swarm_connect(args)
    print("Unknown swarm subcommand. Run `centurion swarm connect -h` or `centurion swarm link -h`.", file=sys.stderr)
    return 1


def add_parser(subparsers) -> None:
    parser = subparsers.add_parser(
        "swarm",
        help="Mission Control project token and sync configuration",
    )
    swarm_sub = parser.add_subparsers(dest="swarm_action")

    link = swarm_sub.add_parser(
        "link",
        help="Link a ctk_inst_* instance token to your customer account",
    )
    link.add_argument("--token", help="ctk_inst_* instance token")
    link.add_argument("--primary-token", dest="primary_token", help="ctk_primary_* token (default: auto-detected from auth.json)")
    link.add_argument("--portal-url", dest="portal_url", help="Portal API base URL (default: personalcenturion.com)")
    link.set_defaults(func=swarm_command)

    connect = swarm_sub.add_parser(
        "connect",
        help="Save ctk_proj token for Mission Control APIs",
    )
    connect.add_argument("--token", help="ctk_proj_* project token")
    connect.add_argument("--install-id", dest="install_id", help="Fleet install_id")
    connect.add_argument("--project-id", dest="project_id", help="Swarm project UUID")
    connect.set_defaults(func=swarm_command)

    parser.set_defaults(func=swarm_command)
