"""Tests for Backup Thinking write helpers (fallback_providers upsert/slot)."""

from __future__ import annotations


def test_upsert_fallback_entry_slot_and_reject_duplicate_identity():
    from centurion_cli.fallback_config import (
        get_fallback_chain,
        remove_fallback_slot,
        upsert_fallback_entry,
    )

    config: dict = {"model": {"provider": "openai-api", "default": "gpt-5.4"}}
    chain = upsert_fallback_entry(
        config,
        {"provider": "anthropic", "model": "claude-sonnet-4-6"},
        slot=1,
    )
    assert len(chain) == 1
    assert chain[0]["provider"] == "anthropic"
    assert config["fallback_providers"][0]["model"] == "claude-sonnet-4-6"
    assert "fallback_model" not in config

    chain = upsert_fallback_entry(
        config,
        {"provider": "deepseek", "model": "deepseek-v4-pro"},
        slot=2,
    )
    assert len(chain) == 2
    assert chain[1]["provider"] == "deepseek"

    # Replace slot 1
    chain = upsert_fallback_entry(
        config,
        {"provider": "xai", "model": "grok-4.3"},
        slot=1,
    )
    assert chain[0]["provider"] == "xai"
    assert chain[1]["provider"] == "deepseek"

    chain = remove_fallback_slot(config, 1)
    assert len(chain) == 1
    assert chain[0]["provider"] == "deepseek"
    assert get_fallback_chain(config) == chain


def test_apply_remote_backup_rejects_primary_and_writes_slot(monkeypatch, tmp_path):
    import copy

    from centurion_cli import provider_control as pc

    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    config = {
        "model": {"provider": "openai-api", "default": "gpt-5.4-mini"},
        "fallback_providers": [],
    }

    monkeypatch.setattr(pc, "probe_provider", lambda **_k: (True, "ok", 1))

    def _load():
        return dict(config)

    def _save(cfg):
        config.clear()
        config.update(copy.deepcopy(cfg))

    monkeypatch.setattr("centurion_cli.config.load_config", _load)
    monkeypatch.setattr("centurion_cli.config.save_config", _save)

    # Reject same as primary (openai-luna is gpt-5.4-mini / openai-api)
    denied = pc.apply_remote_backup("openai-luna", slot=1, probe=False)
    assert denied.ok is False
    assert "primary" in denied.message.lower()

    ok = pc.apply_remote_backup("anthropic-sonnet-5", slot=1, probe=False)
    assert ok.ok is True
    assert config["fallback_providers"][0]["provider"] == "anthropic"

    cleared = pc.remove_remote_backup(slot=1)
    assert cleared.ok is True
    assert config.get("fallback_providers") == []
