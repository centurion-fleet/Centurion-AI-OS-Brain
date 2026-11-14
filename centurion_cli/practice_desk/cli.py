"""`centurion practice-desk …` — the thin wrapper the main CLI calls.

Kept out of `centurion_cli/main.py` on purpose: that file is eleven thousand lines
and shared with other builds, so the only entry it gets is one parser block and
one function reference. Everything else lives here.
"""

from __future__ import annotations

import sys


def cmd_practice_desk(args) -> int:
    """Hand the remaining argv to the practice desk's own parser."""
    from centurion_cli.practice_desk.__main__ import main as desk_main

    argv = list(getattr(args, "practice_args", []) or [])
    if not argv:
        from centurion_cli.practice_desk.__main__ import build_parser

        build_parser().print_help()
        return 0
    return desk_main(argv)


def register_cli(subparsers) -> None:
    """Attach `practice-desk` to the top-level parser. Called from main()."""
    import argparse

    parser = subparsers.add_parser(
        "practice-desk",
        help="The signed-in browser client for a Centurion practice",
        description=(
            "Run the practice desk: a passkey-signed-in browser client where each "
            "named user has their own session, the practice shares client threads, "
            "and a draft reaches a client only after a partner signs it."
        ),
    )
    parser.add_argument(
        "practice_args",
        nargs=argparse.REMAINDER,
        help=(
            "subcommand and options: serve, invite, people, drafts, deadlines, "
            "demo, audit, suspend, revoke"
        ),
    )
    parser.set_defaults(func=cmd_practice_desk)


if __name__ == "__main__":  # pragma: no cover
    sys.exit(0)
