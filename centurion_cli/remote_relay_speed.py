"""Away-path speed helpers — transport RTT markers (no PII).

Used by soak scripts and optional Brain-side logging. Budgets live in
``brain/linux/docs/REMOTE_RELAY.md`` (Workstream C).
"""

from __future__ import annotations

from dataclasses import dataclass
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
        "away": away,
        "p50_ms": p50,
        "p95_ms": p95,
        "limit_p50_ms": limit50,
        "limit_p95_ms": limit95,
        "n": len(samples_ms),
    }
