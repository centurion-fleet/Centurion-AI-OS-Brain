"""Tests for centurion_cli.support_control."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from centurion_cli import support_control as sc
from centurion_cli.remote_bridge import handle_request


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text(
        "model:\n  provider: openrouter\n  default: anthropic/claude-sonnet-4\n",
        encoding="utf-8",
    )
    return home


def test_support_code_format(centurion_home, monkeypatch):
    monkeypatch.setattr(
        sc,
        "collect_health_snapshot",
        lambda **_kw: sc.HealthSnapshot(
            thinking_health=sc._THINKING_WORKING,
            last_good_available=False,
        ),
    )
    result = sc.create_support_bundle(probe=False)
    assert result.ok
    assert len(result.code) == 7
    assert result.code[3] == "-"
    assert result.code.replace("-", "").isalnum()


def test_bundle_round_trip(centurion_home, monkeypatch):
    monkeypatch.setattr(
        sc,
        "collect_health_snapshot",
        lambda **_kw: sc.HealthSnapshot(
            thinking_health=sc._THINKING_NEEDS_ATTENTION,
            last_good_available=True,
            thinking_message="Needs attention.",
        ),
    )
    created = sc.create_support_bundle(probe=False)
    loaded = sc.lookup_support_bundle(created.code)
    assert loaded is not None
    assert loaded["code"] == created.code
    assert loaded["snapshot"]["thinking_health"] == sc._THINKING_NEEDS_ATTENTION


def test_bundle_expired_removed(centurion_home, monkeypatch):
    monkeypatch.setattr(
        sc,
        "collect_health_snapshot",
        lambda **_kw: sc.HealthSnapshot(thinking_health=sc._THINKING_UNKNOWN),
    )
    created = sc.create_support_bundle(probe=False)
    path = sc._bundles_dir() / f"{created.code}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    expired = datetime.now(timezone.utc) - timedelta(hours=1)
    data["expires_at"] = expired.strftime("%Y-%m-%dT%H:%M:%SZ")
    path.write_text(json.dumps(data), encoding="utf-8")
    assert sc.lookup_support_bundle(created.code) is None
    assert not path.exists()


def test_plain_summary_with_lkg():
    summary = sc._plain_summary(
        thinking_health=sc._THINKING_NEEDS_ATTENTION,
        last_good_available=True,
    )
    assert "needs attention" in summary.lower()
    assert "Last working setup" in summary


def test_auto_fix_success(monkeypatch, centurion_home):
    monkeypatch.setattr(
        sc,
        "restore_last_known_good",
        lambda **_kw: type(
            "R",
            (),
            {"ok": True, "message": "Restored your last working setup."},
        )(),
    )
    monkeypatch.setattr(
        sc,
        "collect_health_snapshot",
        lambda **_kw: sc.HealthSnapshot(thinking_health=sc._THINKING_WORKING),
    )
    result = sc.auto_fix_thinking(probe=False)
    assert result.ok
    assert result.restored
    assert "normally" in result.message.lower()


def test_remote_bridge_health_check(monkeypatch):
    monkeypatch.setattr(
        sc,
        "collect_health_snapshot",
        lambda **_kw: sc.HealthSnapshot(
            thinking_health=sc._THINKING_WORKING,
            thinking_message="Working normally.",
        ),
    )
    response = handle_request({"id": "h1", "action": "health_check"})
    assert response["ok"] is True
    assert response["thinking_health"] == sc._THINKING_WORKING


def test_remote_bridge_support_bundle(monkeypatch, centurion_home):
    monkeypatch.setattr(
        sc,
        "create_support_bundle",
        lambda **_kw: sc.SupportBundleResult(
            ok=True,
            code="ABC-123",
            summary="Needs attention.",
            thinking_health=sc._THINKING_NEEDS_ATTENTION,
        ),
    )
    response = handle_request({"id": "b1", "action": "support_bundle"})
    assert response["ok"] is True
    assert response["code"] == "ABC-123"


def test_remote_bridge_support_auto_fix(monkeypatch):
    monkeypatch.setattr(
        sc,
        "auto_fix_thinking",
        lambda **_kw: sc.AutoFixResult(
            ok=True,
            message="Restored.",
            thinking_health=sc._THINKING_WORKING,
            restored=True,
        ),
    )
    response = handle_request({"id": "f1", "action": "support_auto_fix"})
    assert response["ok"] is True
    assert response["restored"] is True


def test_list_backup_thinking_services(centurion_home):
    (centurion_home / "config.yaml").write_text(
        "model:\n  provider: openrouter\n  default: anthropic/claude-sonnet-4\n"
        "fallback_providers:\n"
        "  - provider: openai\n"
        "    model: gpt-4o\n",
        encoding="utf-8",
    )
    backups = sc.list_backup_thinking_services()
    assert len(backups) == 1
    assert "gpt-4o" in backups[0]["label"]


def test_format_bundle_for_display():
    body = sc.format_bundle_for_display(
        {
            "summary_plain": "Needs attention.",
            "snapshot": {"issues": ["Missing API key on host."]},
            "recent_errors": ["ERROR probe failed"],
        }
    )
    assert "Needs attention" in body
    assert "Missing API key" in body
    assert "Recent errors" in body
