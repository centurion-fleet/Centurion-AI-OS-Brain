"""Remote Brain chat must hard-override Hermes-weight identity each turn."""

from __future__ import annotations


def test_scrub_replaces_hermes_assistant_turns():
    from centurion_cli.remote_bridge import _scrub_foreign_identity_history

    history = [
        {"role": "user", "content": "hi"},
        {"role": "assistant", "content": "I am Hermes Agent by Nous Research."},
        {"role": "user", "content": "what's your name?"},
    ]
    cleaned = _scrub_foreign_identity_history(history, "Titus")
    assert cleaned[1]["role"] == "assistant"
    assert "Titus" in cleaned[1]["content"]
    assert "Hermes" not in cleaned[1]["content"] or "not Hermes" in cleaned[1]["content"]
    assert cleaned[0]["content"] == "hi"


def test_remote_identity_ephemeral_names_titus():
    from centurion_cli.remote_bridge import _remote_identity_ephemeral

    text = _remote_identity_ephemeral("Titus")
    assert "Titus" in text
    assert "NOT Hermes" in text
    assert "Centurion Fleet" in text
