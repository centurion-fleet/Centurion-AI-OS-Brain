"""Tests for centurion_cli.provider_control."""

from __future__ import annotations

import json
from unittest.mock import patch

import pytest
import yaml

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
        new_model="claude-sonnet-4-6",
        target_provider="anthropic",
        provider_changed=True,
        api_key="test-key",
        base_url="https://api.anthropic.com",
        api_mode="chat_completions",
    )

    monkeypatch.setattr(pc, "_resolve_switch", lambda _p, _m: switch_result)
    monkeypatch.setattr(
        pc,
        "probe_provider",
        lambda **_kw: (True, "", 15),
    )

    result = pc.apply_switch("anthropic", "claude-sonnet-4-6", probe=True)
    assert result.ok
    assert result.provider == "anthropic"
    assert result.model == "claude-sonnet-4-6"

    cfg = yaml.safe_load((centurion_home / "config.yaml").read_text(encoding="utf-8"))
    assert cfg["model"]["provider"] == "anthropic"
    assert cfg["model"]["default"] == "claude-sonnet-4-6"
    assert pc.load_last_known_good() is not None


def test_apply_switch_blocks_openrouter():
    result = pc.apply_switch("openrouter", "anthropic/claude-sonnet-4", probe=False)
    assert not result.ok
    assert result.code == pc.LLM_CONFIG_INVALID
    assert "OpenRouter" in result.message


def test_validate_switch_blocks_openrouter():
    result = pc.validate_switch("openrouter", "anthropic/claude-sonnet-4", probe=False)
    assert not result.ok
    assert result.code == pc.LLM_CONFIG_INVALID


def test_save_remote_api_key_persists_without_echo(monkeypatch, centurion_home):
    saved: dict[str, str] = {}

    def _fake_save(key: str, value: str) -> None:
        saved[key] = value

    monkeypatch.setattr("centurion_cli.config.is_managed", lambda: False)
    monkeypatch.setattr("centurion_cli.config.save_env_value", _fake_save)

    secret = "sk-test-secret-do-not-echo"
    result = pc.save_remote_api_key("anthropic-sonnet-5", secret)
    assert result["ok"] is True
    assert result["configured"] is True
    assert saved.get("ANTHROPIC_API_KEY") == secret
    blob = json.dumps(result)
    assert secret not in blob
    assert "sk-test" not in blob


def test_provider_cli_save_key_json_redacts_secret(monkeypatch, centurion_home, capsys):
    from centurion_cli import provider_cli

    monkeypatch.setattr("centurion_cli.config.is_managed", lambda: False)
    monkeypatch.setattr(
        "centurion_cli.config.save_env_value",
        lambda _k, _v: None,
    )
    args = type(
        "Args",
        (),
        {"connector_id": "anthropic-sonnet-5", "key": "sk-never-print-me", "json": True},
    )()
    code = provider_cli._cmd_save_key(args)
    assert code == 0
    out = capsys.readouterr().out
    assert "sk-never-print-me" not in out
    payload = json.loads(out)
    assert payload["ok"] is True
    assert "key" not in payload


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
        "centurion_cli.remote_bridge.get_status",
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
        "centurion_cli.remote_bridge.restore_last_known_good",
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
