"""Tests for centurion_cli.herald."""

from __future__ import annotations

import pytest

from centurion_cli.herald.service import (
    HeraldChatRequest,
    HeraldContext,
    _normalize_support_code,
    _redact_text,
    chat,
    suggest_actions,
)


def test_redact_api_key_patterns():
    text = "my key is sk-abcdefghijklmnopqrstuvwxyz123456"
    assert "sk-" not in _redact_text(text)


def test_support_code_normalization():
    assert _normalize_support_code("abcdef") == "ABC-DEF"
    assert _normalize_support_code("ABC-DEF") == "ABC-DEF"
    assert _normalize_support_code("bad") == ""


def test_suggest_actions_disconnected():
    ctx = HeraldContext(connection_state="disconnected")
    ids = [a.id for a in suggest_actions(ctx)]
    assert "open_connect" in ids


def test_suggest_actions_thinking_broken():
    ctx = HeraldContext(connection_state="connected", thinking_health="needs_attention")
    ids = [a.id for a in suggest_actions(ctx)]
    assert "try_auto_fix" in ids
    assert "open_get_help" in ids


def test_chat_requires_user_message():
    req = HeraldChatRequest(install_id="install-abc-12345", messages=[])
    result = chat(req)
    assert not result.ok


def test_chat_fallback_without_api_key(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("CENTURION_HERALD_OPENAI_API_KEY", raising=False)
    req = HeraldChatRequest.from_payload(
        {
            "install_id": "install-abc-12345",
            "messages": [{"role": "user", "content": "I cannot connect"}],
            "context": {"connection_state": "disconnected"},
        }
    )
    result = chat(req)
    assert result.ok
    assert "Herald" in result.reply
    assert any(a.id == "open_connect" for a in result.suggested_actions)


def test_chat_strips_secrets_from_context():
    req = HeraldChatRequest.from_payload(
        {
            "install_id": "install-abc-12345",
            "messages": [{"role": "user", "content": "help"}],
            "context": {
                "thinking_message": "failed sk-secretkey1234567890abcdef",
                "mission_summary": "Bearer abc.def.ghi",
            },
        }
    )
    assert "[redacted]" in req.context.thinking_message
    assert "[redacted]" in req.context.mission_summary
