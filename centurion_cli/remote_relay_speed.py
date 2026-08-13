"""Away-path speed helpers — transport RTT / TTFT markers (no PII).

Used by soak scripts and optional Brain-side logging. Budgets live in
``brain/linux/docs/REMOTE_RELAY.md`` (Workstream C).

CLI (fixture / soak helper)::

    python -m centurion_cli.remote_relay_speed --demo
    python -m centurion_cli.remote_relay_speed --rtt 12,18,22 --away
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True)
class SpeedBudget:
    """Exit gates for Centurion Remote transport overhead."""

    lan_rtt_p50_ms: float = 50.0
    lan_rtt_p95_ms: float = 150.0
    away_rtt_p50_ms: float = 200.0
    away_rtt_p95_ms: float = 500.0
    lan_ttft_overhead_p95_ms: float = 100.0
    away_ttft_overhead_p95_ms: float = 400.0
    away_cold_connect_p95_ms: float = 3000.0
    lan_approval_appear_p95_ms: float = 300.0
    away_approval_appear_p95_ms: float = 800.0


DEFAULT_SPEED_BUDGET = SpeedBudget()


def percentile(samples_ms: list[float], p: float) -> float | None:
    if not samples_ms:
        return None
    ordered = sorted(samples_ms)
    if len(ordered) == 1:
        return ordered[0]
    rank = max(0, min(len(ordered) - 1, int(round((p / 100.0) * (len(ordered) - 1)))))
    return ordered[rank]


def evaluate_rtt(
    samples_ms: list[float],
    *,
    away: bool,
    budget: SpeedBudget = DEFAULT_SPEED_BUDGET,
) -> dict[str, Any]:
    """Return pass/fail for transport RTT samples (ping or empty bridge)."""
    p50 = percentile(samples_ms, 50)
    p95 = percentile(samples_ms, 95)
    limit50 = budget.away_rtt_p50_ms if away else budget.lan_rtt_p50_ms
    limit95 = budget.away_rtt_p95_ms if away else budget.lan_rtt_p95_ms
    ok = (
        p50 is not None
        and p95 is not None
        and p50 <= limit50
        and p95 <= limit95
    )
    return {
        "ok": ok,
        "metric": "rtt",
        "away": away,
        "p50_ms": p50,
        "p95_ms": p95,
        "limit_p50_ms": limit50,
        "limit_p95_ms": limit95,
        "n": len(samples_ms),
    }


def evaluate_ttft_overhead(
    samples_ms: list[float],
    *,
    away: bool,
    budget: SpeedBudget = DEFAULT_SPEED_BUDGET,
) -> dict[str, Any]:
    """Pass/fail for transport+queue overhead until first streamed UI token."""
    p95 = percentile(samples_ms, 95)
    limit = budget.away_ttft_overhead_p95_ms if away else budget.lan_ttft_overhead_p95_ms
    ok = p95 is not None and p95 <= limit
    return {
        "ok": ok,
        "metric": "ttft_overhead",
        "away": away,
        "p95_ms": p95,
        "limit_p95_ms": limit,
        "n": len(samples_ms),
    }


def evaluate_cold_connect(
    samples_ms: list[float],
    *,
    budget: SpeedBudget = DEFAULT_SPEED_BUDGET,
) -> dict[str, Any]:
    """Pass/fail for Away cold join + re-KX (once per conn epoch)."""
    p95 = percentile(samples_ms, 95)
    limit = budget.away_cold_connect_p95_ms
    ok = p95 is not None and p95 <= limit
    return {
        "ok": ok,
        "metric": "cold_connect",
        "away": True,
        "p95_ms": p95,
        "limit_p95_ms": limit,
        "n": len(samples_ms),
    }


def evaluate_approval_appear(
    samples_ms: list[float],
    *,
    away: bool,
    budget: SpeedBudget = DEFAULT_SPEED_BUDGET,
) -> dict[str, Any]:
    """Pass/fail for time until approval UI appears after send (Workstream C)."""
    p95 = percentile(samples_ms, 95)
    limit = (
        budget.away_approval_appear_p95_ms if away else budget.lan_approval_appear_p95_ms
    )
    ok = p95 is not None and p95 <= limit
    return {
        "ok": ok,
        "metric": "approval_appear",
        "away": away,
        "p95_ms": p95,
        "limit_p95_ms": limit,
        "n": len(samples_ms),
    }


def summarize_speed_report(
    *,
    away: bool,
    rtt_ms: list[float] | None = None,
    ttft_overhead_ms: list[float] | None = None,
    cold_connect_ms: list[float] | None = None,
    approval_appear_ms: list[float] | None = None,
    budget: SpeedBudget = DEFAULT_SPEED_BUDGET,
) -> dict[str, Any]:
    """Aggregate Workstream C gates for a soak run (no PII)."""
    checks: list[dict[str, Any]] = []
    if rtt_ms is not None:
        checks.append(evaluate_rtt(rtt_ms, away=away, budget=budget))
    if ttft_overhead_ms is not None:
        checks.append(evaluate_ttft_overhead(ttft_overhead_ms, away=away, budget=budget))
    if away and cold_connect_ms is not None:
        checks.append(evaluate_cold_connect(cold_connect_ms, budget=budget))
    if approval_appear_ms is not None:
        checks.append(evaluate_approval_appear(approval_appear_ms, away=away, budget=budget))
    ok = bool(checks) and all(bool(c.get("ok")) for c in checks)
    return {
        "ok": ok,
        "away": away,
        "budget": asdict(budget),
        "checks": checks,
    }


def _parse_samples(raw: str) -> list[float]:
    parts = [p.strip() for p in raw.replace(";", ",").split(",") if p.strip()]
    return [float(p) for p in parts]


AWAY_DOD_CHECKLIST = (
    "Away-over-relay DoD (gates App Store “anywhere”) — cellular + CGNAT",
    "",
    "[ ] Pair once at home; enable Chat from anywhere on Brain (websockets + Supabase env)",
    "[ ] Leave Wi‑Fi; same topics list and resume over RelayTransport",
    "[ ] Mid-turn tool approval over Away",
    "[ ] Brain offline → clear failure (same honesty as Telegram gateway down)",
    "[ ] Reconnect mid-turn → retryable error; no half-delivered approvals",
    "[ ] Chunked history resume >180KB succeeds; oversize soft-fails cleanly",
    "[ ] Speed budgets green — iPhone Settings → Copy speed soak samples, then:",
    "      python -m centurion_cli.remote_relay_speed --away --rtt … --ttft … --cold …",
    "[ ] Privacy Help linked from Settings / Unbox",
    "",
    "Until all boxes are green, do not unlock App Store “works anywhere” copy.",
    "See brain/linux/docs/REMOTE_RELAY.md",
)


def print_away_dod_checklist(*, file=None) -> None:
    out = sys.stdout if file is None else file
    for line in AWAY_DOD_CHECKLIST:
        print(line, file=out)


def remote_relay_readiness() -> dict[str, Any]:
    """Best-effort Away readiness snapshot for soak operators (no PII)."""
    try:
        from centurion_cli import remote_relay_service as rrs

        status = rrs.status()
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    ready = bool(status.get("realtime_pipe_ready")) and bool(
        status.get("websockets_installed")
    )
    return {
        "ok": ready,
        "enabled": bool(status.get("enabled")),
        "websockets_installed": bool(status.get("websockets_installed")),
        "realtime_pipe_ready": bool(status.get("realtime_pipe_ready")),
        "supabase_url_configured": bool(status.get("supabase_url_configured")),
        "hint": status.get("hint") or "",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate Centurion Remote speed budgets (no network)."
    )
    parser.add_argument("--away", action="store_true", help="Use Away budgets")
    parser.add_argument("--rtt", default="", help="Comma-separated RTT samples in ms")
    parser.add_argument(
        "--ttft",
        default="",
        help="Comma-separated TTFT overhead samples in ms (first UI token)",
    )
    parser.add_argument(
        "--cold",
        default="",
        help="Comma-separated Away cold connect+KX samples in ms",
    )
    parser.add_argument(
        "--approval",
        default="",
        help="Comma-separated approval-appear samples in ms (send → sheet)",
    )
    parser.add_argument(
        "--checklist",
        action="store_true",
        help="Print Away DoD soak checklist (gates App Store anywhere)",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Print Brain remote_relay readiness JSON (when config available)",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Run a green LAN demo + a green Away demo and print JSON",
    )
    parser.add_argument("--json", action="store_true", help="Print machine JSON only")
    args = parser.parse_args(argv)

    if args.checklist:
        print_away_dod_checklist()
        if args.status:
            print("")
            print(json.dumps(remote_relay_readiness(), indent=2))
        return 0

    if args.status and not (
        args.demo or args.rtt or args.ttft or args.cold or args.approval
    ):
        payload = remote_relay_readiness()
        print(json.dumps(payload, indent=2 if not args.json else None))
        return 0 if payload.get("ok") else 1

    if args.demo:
        lan = summarize_speed_report(
            away=False,
            rtt_ms=[12, 18, 22, 28, 35],
            ttft_overhead_ms=[40, 55, 70],
            approval_appear_ms=[80, 120, 200],
        )
        away = summarize_speed_report(
            away=True,
            rtt_ms=[120, 150, 180, 190],
            ttft_overhead_ms=[220, 310, 390],
            cold_connect_ms=[1800, 2200, 2600],
            approval_appear_ms=[300, 450, 600],
        )
        payload = {"lan_demo": lan, "away_demo": away}
        print(json.dumps(payload, indent=2 if not args.json else None))
        return 0 if lan["ok"] and away["ok"] else 1

    report = summarize_speed_report(
        away=bool(args.away),
        rtt_ms=_parse_samples(args.rtt) if args.rtt else None,
        ttft_overhead_ms=_parse_samples(args.ttft) if args.ttft else None,
        cold_connect_ms=_parse_samples(args.cold) if args.cold else None,
        approval_appear_ms=_parse_samples(args.approval) if args.approval else None,
    )
    if not report["checks"]:
        parser.error(
            "Provide --rtt / --ttft / --cold / --approval samples, or --demo / --checklist / --status"
        )
    print(json.dumps(report, indent=2 if not args.json else None))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
