"""CLI for Adrian support guide server (`centurion adrian serve`)."""

from __future__ import annotations

import argparse


def adrian_command(args: argparse.Namespace) -> None:
    sub = getattr(args, "adrian_command", None)
    if sub == "serve":
        from centurion_cli.adrian.server import serve

        serve(host=args.host, port=args.port)
        return
    print("usage: centurion adrian serve [--host HOST] [--port PORT]", flush=True)
    raise SystemExit(2)


def register_subparser(subparsers) -> None:
    adrian_parser = subparsers.add_parser(
        "adrian",
        help="Centurion Adrian — cloud support guide for CenturionAI Remote",
        description=(
            "Operate Adrian, Centurion's customer-facing support guide. "
            "Customers never bring API keys — Centurion hosts the model."
        ),
    )
    adrian_sub = adrian_parser.add_subparsers(dest="adrian_command", required=True)

    serve_parser = adrian_sub.add_parser(
        "serve",
        help="Run the Adrian HTTP API (production: adrian.centurion.ai)",
    )
    serve_parser.add_argument("--host", default="0.0.0.0")
    serve_parser.add_argument("--port", type=int, default=9120)
    serve_parser.set_defaults(func=adrian_command)

    adrian_parser.set_defaults(func=adrian_command)
