"""CLI for Centurion fleet management — ``centurion fleet …`` subcommand."""

from __future__ import annotations

import argparse
import os
import sys


def _registry_path(args: argparse.Namespace) -> str:
    return getattr(args, "registry", None) or os.path.join(
        os.environ.get("CENTURION_HOME", os.path.expanduser("~/.centurion")),
        "fleet",
        "registry.json",
    )


def fleet_status(args: argparse.Namespace) -> None:
    from centurion.fleet.overseer import OverseerCommandCenter, format_fleet_report
    from centurion.fleet.registry import FleetRegistry

    registry = FleetRegistry(_registry_path(args))
    overseer = OverseerCommandCenter(registry)
    print(format_fleet_report(overseer))


def fleet_list(args: argparse.Namespace) -> None:
    from centurion.fleet.registry import FleetRegistry

    registry = FleetRegistry(_registry_path(args))
    records = registry.list_all()

    print(f"\n{'=' * 60}")
    print(f"  Centurion Fleet — {len(records)} registered")
    print(f"{'=' * 60}")

    for r in records:
        i = r.identity
        s = r.status
        print(
            f"  {i.emoji} {i.name:12s} | {i.owner_name:20s} | "
            f"{i.role:12s} | {s.status:10s} | {s.model:20s}"
        )
    print()


def fleet_show(args: argparse.Namespace) -> None:
    from centurion.fleet.overseer import OverseerCommandCenter
    from centurion.fleet.registry import FleetRegistry

    registry = FleetRegistry(_registry_path(args))
    overseer = OverseerCommandCenter(registry)
    detail = overseer.centurion_detail(args.centurion_id)
    if "error" in detail:
        print(f"Error: {detail['error']}")
        return

    print(f"\n{'=' * 50}")
    print(f"  {detail['identity']['emoji']} {detail['identity']['name']}")
    print(f"  {detail['identity']['id']}")
    print(f"{'=' * 50}")
    print(f"  Owner:  {detail['identity']['owner']}")
    print(f"  Role:   {detail['identity']['role']}")
    print(f"  Status: {detail['status']['status']}")
    print(f"  Host:   {detail['status']['host']}")
    print(f"  Model:  {detail['status']['model']}")
    print(f"  Memory: {detail['status']['memory']}")
    print(f"  Uptime: {detail['status']['uptime_hours']:.1f}h")

    if detail.get("unresolved_violations"):
        print(f"\n  ⚠ {detail['unresolved_violations']} unresolved violations")
        for v in detail["violations"][:5]:
            print(f"     [{v['severity']}] {v['policy_id']}: {v['detail'][:80]}")

    if detail.get("capabilities"):
        print(f"\n  Capabilities: {', '.join(detail['capabilities'])}")
    print()


def fleet_checkin(args: argparse.Namespace) -> None:
    from centurion.fleet.health import HealthCheckRunner
    from centurion.fleet.registry import FleetRegistry

    centurion_id = args.centurion_id or os.environ.get("CENTURION_ID", "")
    if not centurion_id:
        print("Error: No CENTURION_ID set. Provide --id or set CENTURION_ID env var.")
        sys.exit(1)

    registry = FleetRegistry(
        os.path.join(
            os.environ.get("CENTURION_HOME", os.path.expanduser("~/.centurion")),
            "fleet",
            "registry.json",
        )
    )
    runner = HealthCheckRunner(centurion_id, registry)
    status = args.status or "active"

    if runner.check_in(status=status):
        print(f"✅ {centurion_id} checked in as '{status}'")
    else:
        print(f"❌ {centurion_id} not found in registry")
        sys.exit(1)

    if getattr(args, "cloud", False):
        from centurion_cli.fleet_cloud import cloud_checkin_from_cli

        sys.exit(cloud_checkin_from_cli())


def fleet_policies(args: argparse.Namespace) -> None:
    from centurion.policies.engine import PolicyStore

    store = PolicyStore()

    if args.action == "list":
        for cat in store.list_categories():
            policies = store.get_policies_by_category(cat)
            print(f"\n  [{cat.upper()}]")
            for p in policies:
                print(
                    f"    {p.policy_id:12s} | {p.title:35s} | "
                    f"v{p.version:5s} | {p.enforce_level:10s}"
                )
        print()
    elif args.action == "seed":
        count = store.seed_default_policies()
        print(f"Seeded {count} default policies")
    elif args.action == "violations":
        violations = store.get_violations(
            centurion_id=args.centurion_id,
            unresolved_only=args.unresolved,
        )
        print(f"\n  {'=' * 50}")
        print(f"  Policy Violations ({len(violations)})")
        print(f"  {'=' * 50}")
        for v in violations:
            print(f"  [{v.severity}] {v.centurion_id} violated {v.policy_id}")
            print(f"       {v.detail[:100]}")
        print()
    else:
        print(f"Unknown action: {args.action}")
        sys.exit(1)


def fleet_deploy(args: argparse.Namespace) -> None:
    from centurion.install.deploy import CenturionDeployer

    deployer = CenturionDeployer(
        name=args.name,
        owner_name=args.owner,
        owner_email=args.owner_email,
        soul_template=args.soul_template,
        centurion_id=args.centurion_id,
        model=args.model,
        provider=args.provider,
        telegram_token=args.telegram_token,
        api_key=args.api_key,
        install_path=args.install_path,
    )
    deployer.deploy()


def _add_fleet_subcommands(
    parser: argparse.ArgumentParser,
    *,
    registry_help: str = "Path to fleet registry",
) -> None:
    parser.add_argument("--registry", help=registry_help)

    sub = parser.add_subparsers(dest="fleet_command")

    p_status = sub.add_parser("status", help="Show fleet health")
    p_status.set_defaults(func=fleet_status)

    p_list = sub.add_parser("list", help="List all Centurions")
    p_list.set_defaults(func=fleet_list)

    p_show = sub.add_parser("show", help="Show Centurion details")
    p_show.add_argument("centurion_id", help="Centurion ID (e.g., prefect, cent-004)")
    p_show.set_defaults(func=fleet_show)

    p_ci = sub.add_parser("checkin", help="Send health check heartbeat")
    p_ci.add_argument("--id", dest="centurion_id", help="Centurion ID (default: $CENTURION_ID)")
    p_ci.add_argument("--status", default="active", help="Status to report")
    p_ci.add_argument(
        "--cloud",
        action="store_true",
        help="Also POST check-in to Centurion cloud portal (requires OPENROUTER_API_KEY)",
    )
    p_ci.set_defaults(func=fleet_checkin)

    p_pol = sub.add_parser("policies", help="Manage fleet policies")
    p_pol.add_argument("action", choices=["list", "seed", "violations"])
    p_pol.add_argument("--centurion-id", help="Filter violations by Centurion")
    p_pol.add_argument(
        "--unresolved",
        action="store_true",
        default=True,
        help="Show only unresolved violations",
    )
    p_pol.set_defaults(func=fleet_policies)

    p_dep = sub.add_parser("deploy", help="Deploy a new Centurion")
    p_dep.add_argument("--name", required=True, help="Centurion name")
    p_dep.add_argument("--owner", required=True, help="Owner name")
    p_dep.add_argument("--owner-email", default="", help="Owner email")
    p_dep.add_argument(
        "--soul-template",
        default="default",
        choices=["yeshi", "titus", "default"],
    )
    p_dep.add_argument("--centurion-id", help="Override Centurion ID")
    p_dep.add_argument("--model", default="deepseek-v4-flash")
    p_dep.add_argument("--provider", default="deepseek")
    p_dep.add_argument("--telegram-token", help="Telegram bot token")
    p_dep.add_argument("--api-key", help="API key")
    p_dep.add_argument("--install-path", help="Custom install path")
    p_dep.set_defaults(func=fleet_deploy)

    _add_fleet_peer_subcommands(sub)


# ── Fleet peer pairing (brain-to-brain) ──────────────────────────────
#
# Added 23 Sep 2026, for Adrian's Australian customers.
#
# Before this there was NO CLI at all for registering a peer address — the
# only route was hand-writing ~/.centurion/fleet/peers.json, which is not
# something a customer can be asked to do. Combined with the API server's
# fleet routes never being registered, and those routes never checking
# auth, brain-to-brain was triply unfinished. This is the last piece: two
# Brains become connectable with one command, and the command *proves* the
# link rather than assuming it.
#
# Deliberately fail-visible: `connect` does not print success unless it has
# actually reached the other Brain and been accepted by it.


def _peer_http(url: str, token: str, payload: dict | None = None, timeout: float = 12.0):
    """Call a peer's fleet endpoint. Returns (ok, status, body_dict_or_text)."""
    import json as _json
    import urllib.error
    import urllib.request

    data = _json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Centurion-Auth": token or "",
            "X-Centurion-ID": os.environ.get("CENTURION_ID", "this-brain"),
        },
        method="POST" if data is not None else "GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", errors="replace")
            try:
                return True, r.status, _json.loads(raw)
            except Exception:
                return True, r.status, raw
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            return False, e.code, _json.loads(body)
        except Exception:
            return False, e.code, body
    except Exception as e:
        return False, 0, f"{type(e).__name__}: {e}"


def fleet_peer_list(args: argparse.Namespace) -> None:
    from centurion.fleet.peers import FleetPeers

    peers = FleetPeers().list_all()
    if not peers:
        print("No fleet peers registered.")
        print()
        print("Connect one with:")
        print("  centurion fleet peer connect <http://their-address:port> --token <shared-secret>")
        return
    print(f"{'ID':<22} {'NAME':<20} {'STATUS':<10} ADDRESS")
    for p in peers:
        print(f"{p.centurion_id:<22} {(p.name or '-'):<20} {(p.status or 'unknown'):<10} {p.address}")


def fleet_peer_add(args: argparse.Namespace) -> None:
    from centurion.fleet.peers import FleetPeer, FleetPeers

    address = args.address.rstrip("/")
    peers = FleetPeers()
    peers.register(
        FleetPeer(
            centurion_id=args.centurion_id,
            name=args.name or args.centurion_id,
            address=address,
            auth_token=args.token or "",
            status="unknown",
        )
    )
    print(f"Registered '{args.centurion_id}' at {address}.")
    print("Run 'centurion fleet peer test %s' to prove the link." % args.centurion_id)


def fleet_peer_remove(args: argparse.Namespace) -> None:
    from centurion.fleet.peers import FleetPeers

    ok = FleetPeers().remove(args.centurion_id)
    print(f"{'Removed' if ok else 'Not found:'} {args.centurion_id}")


def fleet_peer_test(args: argparse.Namespace) -> None:
    from centurion.fleet.peers import FleetPeers

    peer = FleetPeers().get(args.centurion_id)
    if not peer:
        print(f"No such peer: {args.centurion_id}")
        print("Run 'centurion fleet peer list' to see who is registered.")
        return

    ok, status, body = _peer_http(f"{peer.address.rstrip('/')}/fleet/status", peer.auth_token)
    if ok:
        count = body.get("count") if isinstance(body, dict) else "?"
        print(f"REACHABLE — {peer.name} answered (HTTP {status}, {count} peer(s) on their side).")
    elif status == 401:
        print(f"REFUSED (401) — reached {peer.name}, but our token was not accepted.")
        print("Check that both machines were given the same shared secret.")
    else:
        print(f"UNREACHABLE — {peer.name} did not answer at {peer.address}")
        print(f"  detail: {body}")


def fleet_peer_connect(args: argparse.Namespace) -> None:
    """Pair with another Brain: prove the link, then remember it."""
    import json as _json
    import socket as _sock

    from centurion.fleet.peers import FleetPeer, FleetPeers

    address = args.address.rstrip("/")
    if not address.startswith("http"):
        address = f"http://{address}"
    token = args.token or os.environ.get("CENTURION_FLEET_TOKEN", "")

    print(f"Pairing with {address} …")

    # 1. Can we reach it at all?
    ok, status, body = _peer_http(f"{address}/fleet/status", token)
    if not ok:
        if status == 401:
            print("  ✗ Reached the machine, but it refused our token.")
            print("    Both Brains must be given the SAME shared secret (--token).")
        elif status == 404:
            print("  ✗ Reached the machine, but it has no fleet endpoint.")
            print("    That Brain is running an older build — it needs the update first.")
        elif status == 0:
            print(f"  ✗ Could not reach it: {body}")
            print("    If you are both on the SAME WiFi, check that:")
            print("      • they ran 'centurion fleet peer enable' and RESTARTED the Brain")
            print("      • you are using their address, not yours (it is printed by enable)")
            print("    If you are on DIFFERENT networks, port forwarding is also needed.")
        else:
            print(f"  ✗ Unexpected reply (HTTP {status}): {body}")
        return

    # 2. Introduce ourselves so the pairing is mutual and provable.
    my_id = args.centurion_id or os.environ.get("CENTURION_ID") or _sock.gethostname()
    my_name = args.name or my_id
    ok2, status2, body2 = _peer_http(
        f"{address}/fleet/checkin",
        token,
        {"centurion_id": my_id, "name": my_name, "version": args.version or ""},
    )
    if not ok2:
        print(f"  ✗ Their endpoint answered, but rejected our check-in (HTTP {status2}): {body2}")
        return

    # 3. Only now is it real — record it.
    peers = FleetPeers()
    peers.register(
        FleetPeer(
            centurion_id=args.peer_id or address,
            name=args.peer_name or address,
            address=address,
            auth_token=token,
            status="online",
            last_seen=__import__("time").time(),
        )
    )
    print("  ✓ Link proven — they answered and accepted us.")
    print(f"  ✓ Saved as peer '{args.peer_id or address}'.")
    print()
    print("Next: run 'centurion fleet status' to see the pair.")


def _centurion_home() -> str:
    return os.environ.get("CENTURION_HOME", os.path.expanduser("~/.centurion"))


def _api_server_node(cfg, create: bool = False):
    """
    Return the live api_server config node.

    ⚠️ The real location is `gateway.platforms.api_server`. A stale top-level
    `platforms:` key also exists in some configs and contains only whatsapp —
    writing there silently does nothing while appearing to succeed. Always
    prefer the gateway node.
    """
    gw = cfg.get("gateway")
    if isinstance(gw, dict):
        plats = gw.get("platforms")
        if isinstance(plats, dict):
            if "api_server" in plats or create:
                return plats.setdefault("api_server", {}) if create else plats.get("api_server")
    if create:
        gw = cfg.setdefault("gateway", {})
        plats = gw.setdefault("platforms", {})
        return plats.setdefault("api_server", {})
    plats = cfg.get("platforms")
    if isinstance(plats, dict):
        return plats.get("api_server")
    return None


def write_env_settings(env_path: str, values: dict[str, str]) -> None:
    """Set keys in a .env file, replacing any existing line for each key.

    The gateway's config loader builds its platform configuration from the
    top-level ``platforms:`` block plus environment variables — it does NOT
    read ``gateway.platforms.*``. Anything the fleet feature needs the gateway
    to honour must therefore be written here as well, not only into
    config.yaml. Writing the config node alone is what left the peer listener
    bound to its 127.0.0.1 defaults and unreachable by every other Brain.
    """
    lines: list[str] = []
    if os.path.exists(env_path):
        with open(env_path) as fh:
            lines = fh.readlines()
    for key, value in values.items():
        prefix = f"{key}="
        for i, line in enumerate(lines):
            if line.startswith(prefix):
                lines[i] = f"{key}={value}\n"
                break
        else:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            lines.append(f"{key}={value}\n")
    with open(env_path, "w") as fh:
        fh.writelines(lines)


def fleet_peer_enable(args: argparse.Namespace) -> None:
    """
    Make this Brain reachable by other Brains.

    A Brain ships listening on 127.0.0.1 only, so out of the box no other
    machine can reach it. This turns that on and sets the two secrets the
    gateway insists on before it will accept network traffic.

    Deliberately prints everything the customer needs to finish the job
    (what to forward on the router, and the secret to share) because the
    part we cannot do for them is the router.
    """
    import secrets as _secrets
    import socket as _sock

    try:
        from ruamel.yaml import YAML
    except ImportError:
        print("ruamel.yaml is required to edit config safely. Install it first.")
        return

    home = _centurion_home()
    cfg_path = os.path.join(home, "config.yaml")
    env_path = os.path.join(home, ".env")
    if not os.path.exists(cfg_path):
        print(f"No config at {cfg_path} — is this a Centurion Brain?")
        return

    token = args.token or _secrets.token_hex(16)
    port = args.port or 18789

    yaml = YAML()
    yaml.preserve_quotes = True
    with open(cfg_path) as fh:
        cfg = yaml.load(fh)

    api = _api_server_node(cfg, create=True)
    if api is None:
        print("✗ Could not locate the api_server config node. Nothing has changed.")
        return
    api["enabled"] = True
    extra = api.setdefault("extra", {})
    extra["host"] = "0.0.0.0"
    extra["port"] = port
    extra["fleet_token"] = token

    with open(cfg_path, "w") as fh:
        yaml.dump(cfg, fh)

    # Read back and verify, rather than trusting the write.
    with open(cfg_path) as fh:
        check = yaml.load(fh)
    verified = ((_api_server_node(check) or {}).get("extra") or {}).get("host")
    if verified != "0.0.0.0":
        print(f"✗ Could not set the listen address (found {verified!r}). Nothing has changed.")
        print("  Send this to Adrian along with your config.yaml — do not hand-edit it.")
        return

    # Write the settings through .env as well as config.yaml.
    #
    # gateway.platforms.api_server.extra (written above) is NOT read by the
    # gateway's config loader — that assembles platform config from the
    # top-level `platforms:` block plus environment variables. Writing only the
    # config.yaml node left the listener bound to its defaults on
    # 127.0.0.1:8642, so no peer could ever reach it, and the UI reported
    # "nothing is listening yet. Restart the Brain" no matter how many times
    # the customer restarted. These env vars are the path the loader honours.
    write_env_settings(env_path, {
        "API_SERVER_ENABLED": "true",
        "API_SERVER_HOST": "0.0.0.0",
        "API_SERVER_PORT": str(port),
        # Must match the token advertised to peers, or the Brain publishes
        # one secret and accepts none.
        "CENTURION_FLEET_TOKEN": token,
    })

    # The gateway refuses to bind a network address without a real API key.
    api_key = ""
    if os.path.exists(env_path):
        for line in open(env_path):
            if line.startswith("API_SERVER_KEY="):
                api_key = line.split("=", 1)[1].strip()
    if len(api_key) < 8:
        api_key = _secrets.token_hex(24)
        with open(env_path, "a") as fh:
            fh.write(f"\nAPI_SERVER_KEY={api_key}\n")

    # Best-effort: show them the address to give the other side.
    try:
        s = _sock.socket(_sock.AF_INET, _sock.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        lan = s.getsockname()[0]
        s.close()
    except Exception:
        lan = "unknown"

    print("This Brain is now reachable by other Brains.")
    print()
    print(f"  Listening on : 0.0.0.0:{port}")
    print(f"  This machine : {lan}")
    print()
    print("  SHARED SECRET — give this to the other person, and nobody else:")
    print(f"      {token}")
    print()
    print("  Two things still to do:")
    print(f"   1. Restart the Brain so it picks this up.")
    print(f"   2. Give the other machine THIS address:  http://{lan}:{port}")
    print()
    print(f"  Same WiFi? You are done — no router change is needed.")
    print(f"  Different networks? Forward port {port} on your router to {lan}.")
    print()
    print("  Once both sides have done this, pair them with:")
    print(f"      centurion fleet peer connect {lan}:{port} --token <shared secret>")


def fleet_peer_status(args: argparse.Namespace) -> None:
    """Show whether this Brain is reachable and what its secret situation is."""
    try:
        from ruamel.yaml import YAML
    except ImportError:
        print("ruamel.yaml is required to read config safely.")
        return

    cfg_path = os.path.join(_centurion_home(), "config.yaml")
    if not os.path.exists(cfg_path):
        print(f"No config at {cfg_path}")
        return
    with open(cfg_path) as fh:
        cfg = YAML().load(fh)

    extra = (_api_server_node(cfg) or {}).get("extra") or {}
    host = extra.get("host", "127.0.0.1")
    port = extra.get("port", 18789)
    token = extra.get("fleet_token") or os.environ.get("CENTURION_FLEET_TOKEN", "")

    if host in ("127.0.0.1", "localhost", None):
        print("NOT REACHABLE — this Brain only listens on itself.")
        print("Run:  centurion fleet peer enable")
    else:
        print(f"REACHABLE on {host}:{port}")
        print("Shared secret is set." if token else "No shared secret set — remote Brains will be refused.")
    print()
    from centurion.fleet.peers import FleetPeers

    peers = FleetPeers().list_all()
    print(f"Connected Brains: {len(peers)}")
    for p in peers:
        print(f"  {p.centurion_id:<22} {(p.name or '-'):<20} {p.status or 'unknown'}")


def _add_fleet_peer_subcommands(sub) -> None:
    p_peer = sub.add_parser("peer", help="Connect this Brain to another Brain")
    peer_sub = p_peer.add_subparsers(dest="peer_command")

    p_ps = peer_sub.add_parser("status", help="Is this Brain reachable, and who is it connected to?")
    p_ps.set_defaults(func=fleet_peer_status)

    p_pe = peer_sub.add_parser("enable", help="Make this Brain reachable by other Brains")
    p_pe.add_argument("--token", default=None, help="Shared secret (generated if omitted)")
    p_pe.add_argument("--port", type=int, default=None, help="Port (default 18789)")
    p_pe.set_defaults(func=fleet_peer_enable)

    p_pl = peer_sub.add_parser("list", help="Show connected Brains")
    p_pl.set_defaults(func=fleet_peer_list)

    p_pa = peer_sub.add_parser("add", help="Register a Brain by address")
    p_pa.add_argument("centurion_id")
    p_pa.add_argument("address", help="e.g. http://192.168.1.20:18789")
    p_pa.add_argument("--name", default=None)
    p_pa.add_argument("--token", default=None, help="Shared secret")
    p_pa.set_defaults(func=fleet_peer_add)

    p_pr = peer_sub.add_parser("remove", help="Forget a Brain")
    p_pr.add_argument("centurion_id")
    p_pr.set_defaults(func=fleet_peer_remove)

    p_pt = peer_sub.add_parser("test", help="Check whether a connected Brain answers")
    p_pt.add_argument("centurion_id")
    p_pt.set_defaults(func=fleet_peer_test)

    p_pc = peer_sub.add_parser(
        "connect",
        help="Pair with another Brain — reach it, prove the link, remember it",
    )
    p_pc.add_argument("address", help="Their address, e.g. 203.0.113.9:18789")
    p_pc.add_argument("--token", default=None, help="The shared secret both Brains use")
    p_pc.add_argument("--peer-id", dest="peer_id", default=None, help="Name to save them under")
    p_pc.add_argument("--peer-name", dest="peer_name", default=None)
    p_pc.add_argument("--centurion-id", dest="centurion_id", default=None, help="Our own ID")
    p_pc.add_argument("--name", dest="name", default=None, help="Our own display name")
    p_pc.add_argument("--version", default=None)
    p_pc.set_defaults(func=fleet_peer_connect)

    p_peer.set_defaults(func=lambda a: p_peer.print_help())


def build_parser(subparsers: argparse._SubParsersAction) -> argparse.ArgumentParser:
    """Register ``centurion fleet`` on the main CLI argparse tree."""
    fleet_parser = subparsers.add_parser(
        "fleet",
        help="Fleet registry, health, policies, and deployment",
        description="Manage the Centurion fleet (registry, check-ins, policies, deploy)",
    )
    _add_fleet_subcommands(fleet_parser)
    return fleet_parser


def fleet_command(args: argparse.Namespace) -> int:
    """Dispatch ``centurion fleet <subcommand>``."""
    func = getattr(args, "func", None)
    if func is None:
        print("Usage: centurion fleet <status|list|show|checkin|policies|deploy|peer>")
        return 1
    func(args)
    return 0


def run_module_main(argv: list[str] | None = None) -> None:
    """Entry for ``python -m centurion`` — accepts legacy top-level fleet verbs."""
    argv = list(argv if argv is not None else sys.argv[1:])
    if argv and argv[0] == "fleet":
        argv = argv[1:]
    elif argv and argv[0] == "centurion" and len(argv) > 1:
        # legacy: python -m centurion centurion <id> -> show <id>
        argv = ["show", argv[1], *argv[2:]]

    parser = argparse.ArgumentParser(description="Centurion OS — Fleet Management")
    _add_fleet_subcommands(parser)
    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help()
        sys.exit(1)
    args.func(args)
