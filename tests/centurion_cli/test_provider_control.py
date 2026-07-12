"""Tests for centurion_cli.provider_control."""

from __future__ import annotations

import json
from unittest.mock import patch

import pytest

from centurion_cli import provider_control as pc
from centurion_cli.model_switch import ModelSwitchResult
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


def test_lkg_round_trip(centurion_home):
    pc.save_last_known_good(
        provider="openrouter",
        model="anthropic/claude-sonnet-4",
        base_url="",
        probe_latency_ms=42,
    )
    loaded = pc.load_last_known_good()
    assert loaded is not None
    assert loaded["provider"] == "openrouter"
    assert loaded["model"] == "anthropic/claude-sonnet-4"
    assert loaded["probe_latency_ms"] == 42


def test_classify_llm_error_auth_missing():
    code, message = pc.classify_llm_error(
        RuntimeError("No API key was found for provider openrouter")
    )
    assert code == pc.LLM_AUTH_MISSING
    assert "API key" in message


def test_classify_llm_error_model_invalid():
    code, _message = pc.classify_llm_error(RuntimeError("model not found: fake-model"))
    assert code == pc.LLM_MODEL_INVALID


def test_validate_switch_failure(monkeypatch):
    monkeypatch.setattr(
        pc,
        "_resolve_switch",
        lambda _provider, _model: ModelSwitchResult(
            success=False,
            error_message="Unknown provider 'nope'",
        ),
    )
    result = pc.validate_switch("nope", "fake-model", probe=False)
    assert not result.ok
    assert result.code == pc.LLM_CONFIG_INVALID


def test_apply_switch_persists_and_saves_lkg(monkeypatch, centurion_home):
    switch_result = ModelSwitchResult(
        success=True,
        new_model="anthropic/claude-sonnet-4",
        target_provider="openrouter",
        provider_changed=True,
        api_key="test-key",
        base_url="https://openrouter.ai/api/v1",
        api_mode="chat_completions",
    )

    monkeypatch.setattr(pc, "_resolve_switch", lambda _p, _m: switch_result)
    monkeypatch.setattr(
        pc,
        "probe_provider",
        lambda **_kw: (True, "", 15),
    )

    result = pc.apply_switch("openrouter", "anthropic/claude-sonnet-4", probe=True)
    assert result.ok
    assert result.provider == "openrouter"
    assert result.model == "anthropic/claude-sonnet-4"

    cfg = json.loads((centurion_home / "config.yaml").read_text(encoding="utf-8"))
    assert cfg["model"]["provider"] == "openrouter"
    assert cfg["model"]["default"] == "anthropic/claude-sonnet-4"
    assert pc.load_last_known_good() is not None


def test_restore_last_known_good_without_snapshot(centurion_home):
    result = pc.restore_last_known_good(probe=False)
    assert not result.ok
    assert result.code == pc.LLM_CONFIG_INVALID


def test_remote_bridge_structured_chat_error():
    def _boom(_text: str) -> str:
        raise RuntimeError("No API key was found")

    response = handle_request(
        {"id": "req-1", "text": "hello"},
        run_agent=_boom,
    )
    assert response["ok"] is False
    assert response["code"] == pc.LLM_AUTH_MISSING
    assert "retryable" in response


def test_remote_bridge_provider_status(monkeypatch):
    monkeypatch.setattr(
        pc,
        "get_status",
        lambda **_kw: pc.ProviderStatus(
            provider="openrouter",
            model="anthropic/claude-sonnet-4",
            health="ok",
            health_message="Thinking service is reachable.",
        ),
    )
    response = handle_request({"id": "s1", "action": "provider_status"})
    assert response["ok"] is True
    assert response["status"]["provider"] == "openrouter"


def test_remote_bridge_lkg_auto_recovery(monkeypatch):
    pc.save_last_known_good(provider="openrouter", model="anthropic/claude-sonnet-4")

    calls = {"count": 0}

    def _run_agent(text: str) -> str:
        calls["count"] += 1
        if calls["count"] == 1:
            raise RuntimeError("invalid model for provider")
        return f"recovered:{text}"

    monkeypatch.setattr(
        pc,
        "restore_last_known_good",
        lambda **_kw: pc.ApplyResult(
            ok=True,
            provider="openrouter",
            model="anthropic/claude-sonnet-4",
            message="Restored",
        ),
    )

    response = handle_request(
        {"id": "r2", "text": "ping"},
        run_agent=_run_agent,
    )
    assert response["ok"] is True
    assert response.get("recovered") is True
    assert calls["count"] == 2
