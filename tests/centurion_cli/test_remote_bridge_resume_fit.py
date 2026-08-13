"""Soft size fit for remote session resume payloads."""

from __future__ import annotations

from centurion_cli.remote_bridge import _fit_messages_for_remote_payload


def test_fit_messages_under_ceiling_unchanged():
    messages = [{"role": "user", "content": "hi"} for _ in range(5)]
    out, truncated = _fit_messages_for_remote_payload(messages, max_json_chars=50_000)
    assert truncated is False
    assert out == messages


def test_fit_messages_truncates_to_newest():
    messages = [
        {"role": "user", "content": ("x" * 2000) + f"-{i}"}
        for i in range(40)
    ]
    out, truncated = _fit_messages_for_remote_payload(messages, max_json_chars=8_000)
    assert truncated is True
    assert len(out) < len(messages)
    assert out[-1]["content"].endswith("-39")
