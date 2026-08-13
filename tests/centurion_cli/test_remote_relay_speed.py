"""Speed budget helpers for Away / LAN Crypto Chat."""

from __future__ import annotations

from centurion_cli.remote_relay_speed import evaluate_rtt


def test_evaluate_rtt_lan_pass():
    result = evaluate_rtt([10, 20, 30, 40, 45], away=False)
    assert result["ok"] is True
    assert result["p50_ms"] is not None


def test_evaluate_rtt_away_fail_when_slow():
    result = evaluate_rtt([800, 900, 1000], away=True)
    assert result["ok"] is False
    assert result["n"] == 3
