"""CLI for Herald support guide server (`centurion herald serve`)."""

from __future__ import annotations

import argparse


def herald_command(args: argparse.Namespace) -> None:
    sub = getattr(args, "herald_command", None)
    if sub == "serve":
        from centurion_cli.herald.server import serve

        serve(host=args.host, port=args.port)
        return
    print("usage: centurion herald serve [--host HOST] [--port PORT]", flush=True)
    raise SystemExit(2)


def register_subparser(subparsers) -> None:
    herald_parser = subparsers.add_parser(
        "herald",
        help="Centurion Herald — cloud support guide for CenturionAI Remote",
        description=(
            "Operate Herald, Centurion's customer-facing support guide. "
            "Customers never bring API keys — Centurion hosts the model."
        ),
    )
    herald_sub = herald_parser.add_subparsers(dest="herald_command", required=True)

    serve_parser = herald_sub.add_parser(
        "serve",
        help="Run the Herald HTTP API (production: herald.centurion.ai)",
    )
    serve_parser.add_argument("--host", default="0.0.0.0")
    serve_parser.add_argument("--port", type=int, default=9120)
    serve_parser.set_defaults(func=herald_command)

    herald_parser.set_defaults(func=herald_command)
