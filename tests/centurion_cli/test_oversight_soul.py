"""Tests for autonomy / oversight preferences and soul sync."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from centurion_cli.oversight import (
    apply_autonomy_preset,
    build_oversight_guidance,
    get_oversight_snapshot,
    put_oversight_prefs,
    should_enable_remote_yolo,
)
from centurion_cli.remote_bridge import handle_request
from centurion_cli.soul_sync import (
    markdown_to_structured,
    merge_structured_into_soul_md,
    structured_to_markdown,
    write_soul,
)


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text(
        "agent:\n  autonomy_level: balanced\noversight:\n  report_cadence: when_needed\n",
        encoding="utf-8",
    )
    return home


def test_default_autonomy_is_balanced(centurion_home):
    snap = get_oversight_snapshot()
    assert snap["autonomy_level"] == "balanced"
    assert snap["yolo_for_remote"] is False
    assert should_enable_remote_yolo() is False


def test_autonomy_preset_maps_approvals(centurion_home):
    from centurion_cli.config import load_config

    high = apply_autonomy_preset(load_config(), "high")
    assert high["agent"]["autonomy_level"] == "high"
    assert high["approvals"]["mode"] == "off"
    assert high["oversight"]["ask_before_initiative"] is False

    proactive = apply_autonomy_preset(load_config(), "proactive")
    assert proactive["approvals"]["mode"] == "smart"
    assert proactive["oversight"]["ask_before_initiative"] is False

    strict = apply_autonomy_preset(load_config(), "strict")
    assert strict["approvals"]["mode"] == "manual"
    assert strict["oversight"]["ask_before_initiative"] is True


def test_put_oversight_prefs_round_trip(centurion_home):
    snap = put_oversight_prefs(
        {
            "autonomy_level": "proactive",
            "report_cadence": "daily",
            "ask_before_initiative": False,
        }
    )
    assert snap["autonomy_level"] == "proactive"
    assert snap["report_cadence"] == "daily"
    assert snap["approvals_mode"] == "smart"
    assert should_enable_remote_yolo() is False

    high = put_oversight_prefs({"autonomy_level": "high"})
    assert high["yolo_for_remote"] is True
    assert should_enable_remote_yolo() is True


def test_oversight_guidance_includes_level(centurion_home):
    put_oversight_prefs({"autonomy_level": "strict", "report_cadence": "off"})
    text = build_oversight_guidance()
    assert "Strict" in text
    assert "Reporting" in text


def test_soul_structured_round_trip(centurion_home):
    fields = {
        "personalitySummary": "Warm and direct.",
        "tone": "Calm",
        "alwaysDo": ["Lead with headlines"],
        "neverDo": ["Use jargon"],
    }
    md = structured_to_markdown(fields)
    assert "centurion:soul-structured:begin" in md
    parsed = markdown_to_structured(md)
    assert parsed["personalitySummary"] == "Warm and direct."
    assert parsed["alwaysDo"] == ["Lead with headlines"]
    assert parsed["neverDo"] == ["Use jargon"]


def test_soul_merge_preserves_outer_markdown(centurion_home):
    existing = "# Custom intro\n\nKeep me.\n"
    merged = merge_structured_into_soul_md(
        {"personalitySummary": "New personality", "tone": "Warm"},
        existing=existing,
    )
    assert "Keep me." in merged
    assert "New personality" in merged
    again = merge_structured_into_soul_md(
        {"personalitySummary": "Updated", "tone": "Warm"},
        existing=merged,
    )
    assert again.count("centurion:soul-structured:begin") == 1
    assert "Updated" in again
    assert "Keep me." in again


def test_remote_bridge_oversight_actions(centurion_home):
    got = handle_request({"id": "o1", "action": "oversight_get"})
    assert got["ok"] is True
    assert got["oversight"]["autonomy_level"] == "balanced"

    put = handle_request(
        {
            "id": "o2",
            "action": "oversight_put",
            "oversight": {"autonomy_level": "high", "report_cadence": "when_needed"},
        }
    )
    assert put["ok"] is True
    assert put["oversight"]["autonomy_level"] == "high"
    assert put["oversight"]["yolo_for_remote"] is True
    assert "next conversation" in (put.get("message") or "").lower()


def test_remote_bridge_soul_actions(centurion_home):
    put = handle_request(
        {
            "id": "s1",
            "action": "soul_put",
            "soul": {
                "personalitySummary": "A careful companion.",
                "tone": "Measured",
                "alwaysDo": ["Confirm risks"],
            },
        }
    )
    assert put["ok"] is True
    assert put["soul"]["personalitySummary"] == "A careful companion."
    soul_path = Path(os.environ["CENTURION_HOME"]) / "SOUL.md"
    assert soul_path.exists()
    assert "A careful companion." in soul_path.read_text(encoding="utf-8")

    got = handle_request({"id": "s2", "action": "soul_get"})
    assert got["ok"] is True
    assert got["soul"]["tone"] == "Measured"


def test_run_agent_quiet_yolo_gated(centurion_home, monkeypatch):
    from centurion_cli import remote_bridge

    calls: list[str] = []

    def fake_run(text: str) -> str:
        calls.append(os.environ.get("CENTURION_YOLO_MODE", ""))
        return f"ok:{text}"

    monkeypatch.setattr("centurion_cli.oneshot._run_agent", fake_run)

    put_oversight_prefs({"autonomy_level": "balanced"})
    os.environ.pop("CENTURION_YOLO_MODE", None)
    remote_bridge._run_agent_quiet("hello")
    assert calls[-1] == ""

    put_oversight_prefs({"autonomy_level": "high"})
    os.environ.pop("CENTURION_YOLO_MODE", None)
    remote_bridge._run_agent_quiet("hello")
    assert calls[-1] == "1"


def test_write_soul_helper(centurion_home):
    result = write_soul({"personalitySummary": "From helper", "neverDo": ["Spam"]})
    assert result["exists"] is True
    assert result["personalitySummary"] == "From helper"
