"""Speed budget helpers for Away / LAN Crypto Chat."""

from __future__ import annotations

from centurion_cli.remote_relay_speed import (
    evaluate_cold_connect,
    evaluate_rtt,
    evaluate_ttft_overhead,
    main,
    summarize_speed_report,
)


def test_evaluate_rtt_lan_pass():
    result = evaluate_rtt([10, 20, 30, 40, 45], away=False)
    assert result["ok"] is True
    assert result["p50_ms"] is not None


def test_evaluate_rtt_away_fail_when_slow():
    result = evaluate_rtt([800, 900, 1000], away=True)
    assert result["ok"] is False
    assert result["n"] == 3


def test_evaluate_ttft_and_cold():
    ttft = evaluate_ttft_overhead([50, 80, 90], away=False)
    assert ttft["ok"] is True
    cold = evaluate_cold_connect([1000, 1500, 2000])
    assert cold["ok"] is True
    cold_fail = evaluate_cold_connect([4000, 5000, 6000])
    assert cold_fail["ok"] is False


def test_evaluate_approval_appear():
    from centurion_cli.remote_relay_speed import evaluate_approval_appear

    ok = evaluate_approval_appear([100, 150, 200], away=False)
    assert ok["ok"] is True
    fail = evaluate_approval_appear([900, 1000, 1200], away=True)
    assert fail["ok"] is False


def test_summarize_speed_report_away():
    report = summarize_speed_report(
        away=True,
        rtt_ms=[120, 180, 210],
        ttft_overhead_ms=[200, 250, 300],
        cold_connect_ms=[1500, 2000, 2500],
    )
    assert report["ok"] is True
    assert len(report["checks"]) == 3


def test_cli_demo_exit_zero():
    assert main(["--demo", "--json"]) == 0
