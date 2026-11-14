"""`python -m centurion_cli.practice_desk` — run the desk, admit people, look at the record.

Three verbs, deliberately few. Everything that changes who exists goes through
`invite`, and everything that changes what they can do goes through `suspend` or
`revoke` — there is no verb that grants a session directly, because a session is
earned by a passkey and a CLI flag that bypassed that would be the one hole in
the whole design.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from centurion_cli.practice_desk.app import Settings, serve
from centurion_cli.practice_desk.store import DeskError, open_store


def _store(args):
    return open_store(Path(args.db) if getattr(args, "db", None) else None)


def cmd_demo(args) -> int:
    """Write the sample practice. Idempotent, and says where it went."""
    from centurion_cli.practice_desk.demo import build_demo_library

    if args.to:
        root = Path(args.to)
    else:
        from centurion_constants import get_centurion_home

        root = Path(get_centurion_home()) / "practice"

    library = build_demo_library(root)
    clients = sorted((library / "clients").glob("*.md"))
    print(f"Sample practice written to {library}")
    print(f"{len(clients)} clients, a house style and an engagement letter precedent.")
    print("It describes no real person, firm or client — say so when you screen-share.")
    return 0


def cmd_deadlines(args) -> int:
    from centurion_cli.practice_desk import deadlines as dl

    if args.library:
        library = Path(args.library)
    else:
        from centurion_constants import get_centurion_home

        library = Path(get_centurion_home()) / "practice" / "library"

    if not (library / "clients").is_dir():
        print(f"No client library at {library}. Build one with: practice-desk demo", file=sys.stderr)
        return 2

    found = dl.upcoming(library, horizon_days=args.days)
    if not found:
        print(f"Nothing due in the next {args.days} days.")
        return 0
    print(f"{'DUE':12} {'DAYS':>4}  {'CLIENT':26} OBLIGATION")
    for o in found:
        flag = "!" if o.unsettled else " "
        print(f"{o.due.isoformat():12} {o.days_remaining:>4}  {o.client[:26]:26} {o.kind}{flag}")
    unsettled = [o for o in found if o.unsettled]
    if unsettled:
        print()
        print("Unsettled — reported, not guessed:")
        for o in unsettled:
            print(f"  {o.client}: {o.unsettled}")
    return 0


def cmd_serve(args) -> int:
    settings = Settings(
        rp_id=args.rp_id,
        rp_name=args.rp_name,
        origin=args.origin,
        host=args.host,
        port=args.port,
        brain_url=args.brain_url,
        brain_key=args.brain_key,
        brain_model=args.brain_model,
        db_path=Path(args.db) if args.db else None,
        tls_cert=args.tls_cert,
        tls_key=args.tls_key,
        practice_library=Path(args.library) if args.library else None,
    )
    serve(settings)
    return 0


def cmd_invite(args) -> int:
    store = _store(args)
    try:
        person = store.admit_person(
            name=args.name, email=args.email, role=args.role, created_by=args.by
        )
    except DeskError as exc:
        print(f"Refused: {exc}", file=sys.stderr)
        return 2

    token = store.issue_invitation(person.id, by=args.by)
    base = args.origin.rstrip("/")
    print(f"{person.name} <{person.email}> — {person.role}, seat reserved.")
    print()
    print("Send them this link. It works once and expires in fifteen minutes:")
    print(f"  {base}/#invite={token}")
    return 0


def cmd_people(args) -> int:
    store = _store(args)
    people = store.list_people(include_departed=args.all)
    usage = store.seat_usage()
    if not people:
        print("No named users yet. Admit one with: practice-desk invite --name … --email …")
        return 0
    print(f"{'NAME':28} {'EMAIL':34} {'ROLE':15} {'STATUS':10} PASSKEYS")
    for person in people:
        creds = store.credentials_for(person.id)
        print(
            f"{person.name[:28]:28} {person.email[:34]:34} {person.role:15} "
            f"{person.status:10} {len(creds)}"
        )
    print()
    refusal = store.capacity_refusal(1)
    seats = "full" if refusal else "room for one more"
    print(f"{usage['held']} seat(s) held · {seats}")
    return 0


def cmd_suspend(args) -> int:
    store = _store(args)
    person = store.person_by_email(args.email)
    if person is None:
        print(f"No such person: {args.email}", file=sys.stderr)
        return 2
    store.set_status(person.id, args.status, by=args.by)
    print(f"{person.name} is now {args.status}. Their sessions are closed.")
    return 0


def cmd_revoke(args) -> int:
    store = _store(args)
    person = store.person_by_email(args.email)
    if person is None:
        print(f"No such person: {args.email}", file=sys.stderr)
        return 2
    store.revoke_all_credentials(person.id, by=args.by)
    print(f"{person.name}'s passkeys are revoked. Issue a new invitation to re-enrol.")
    return 0


def cmd_audit(args) -> int:
    store = _store(args)
    rows = store.audit_log(limit=args.limit)
    if not rows:
        print("Nothing recorded yet.")
        return 0
    print(f"{'WHEN':20} {'WHO':22} {'ACTION':22} DETAIL")
    for row in rows:
        import datetime

        when = datetime.datetime.fromtimestamp(row["at"]).strftime("%Y-%m-%d %H:%M:%S")
        who = row["person_id"] or "—"
        print(f"{when:20} {who[:22]:22} {row['action'][:22]:22} {row['detail'] or ''}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="practice-desk",
        description="The signed-in browser client for a Centurion practice.",
    )
    parser.add_argument("--db", help="path to practice.db (default: the Centurion home)")
    sub = parser.add_subparsers(dest="command", required=True)

    p_serve = sub.add_parser("serve", help="run the desk")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8765)
    p_serve.add_argument("--rp-id", default="localhost",
                         help="the passkey relying-party id; must be the host name")
    p_serve.add_argument("--rp-name", default="Practice Desk")
    p_serve.add_argument("--origin", default="http://localhost:8765",
                         help="exactly what the browser's address bar shows")
    p_serve.add_argument("--brain-url", default="http://127.0.0.1:18789")
    p_serve.add_argument("--brain-key", default="")
    p_serve.add_argument("--brain-model", default="centurion")
    p_serve.add_argument("--library", help="path to the practice library (clients/)")
    p_serve.add_argument("--tls-cert")
    p_serve.add_argument("--tls-key")
    p_serve.set_defaults(func=cmd_serve)

    p_invite = sub.add_parser("invite", help="reserve a seat and issue a one-time link")
    p_invite.add_argument("--name", required=True)
    p_invite.add_argument("--email", required=True)
    p_invite.add_argument("--role", default="associate",
                          choices=["partner", "manager", "associate", "administrator"])
    p_invite.add_argument("--origin", default="http://localhost:8765")
    p_invite.add_argument("--by")
    p_invite.set_defaults(func=cmd_invite)

    p_people = sub.add_parser("people", help="who is on this machine")
    p_people.add_argument("--all", action="store_true", help="include departed")
    p_people.set_defaults(func=cmd_people)

    p_suspend = sub.add_parser("suspend", help="suspend or reinstate a person")
    p_suspend.add_argument("--email", required=True)
    p_suspend.add_argument("--status", default="suspended",
                           choices=["active", "suspended", "departed"])
    p_suspend.add_argument("--by")
    p_suspend.set_defaults(func=cmd_suspend)

    p_revoke = sub.add_parser("revoke", help="revoke every passkey a person holds")
    p_revoke.add_argument("--email", required=True)
    p_revoke.add_argument("--by")
    p_revoke.set_defaults(func=cmd_revoke)

    p_demo = sub.add_parser("demo", help="write the sample practice (fictional clients)")
    p_demo.add_argument("--to", help="parent directory (default: the Centurion home)")
    p_demo.set_defaults(func=cmd_demo)

    p_dl = sub.add_parser("deadlines", help="what is due, computed from the client library")
    p_dl.add_argument("--days", type=int, default=45)
    p_dl.add_argument("--library")
    p_dl.set_defaults(func=cmd_deadlines)

    p_audit = sub.add_parser("audit", help="what has happened on this machine")
    p_audit.add_argument("--limit", type=int, default=40)
    p_audit.set_defaults(func=cmd_audit)

    # `--db` is accepted before or after the verb. After is the form people
    # actually type, so each subparser carries it too.
    for sub_parser in (
        p_serve, p_invite, p_people, p_suspend, p_revoke, p_demo, p_dl, p_audit
    ):
        sub_parser.add_argument(
            "--db", default=argparse.SUPPRESS, help="path to practice.db"
        )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except DeskError as exc:
        print(f"Refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
