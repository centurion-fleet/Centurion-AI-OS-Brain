"""Remote Brain chat must hard-override foreign identity each turn."""

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
    assert cleaned[1]["content"] == (
        "My name is Titus. I am a Centurion of Centurion Fleet."
    )
    assert "Hermes" not in cleaned[1]["content"]
    assert cleaned[0]["content"] == "hi"


def test_remote_identity_ephemeral_names_titus_without_rivals():
    from centurion_cli.remote_bridge import _remote_identity_ephemeral

    text = _remote_identity_ephemeral("Titus")
    assert "Titus" in text
    assert "Centurion Fleet" in text
    assert "Hermes" not in text
    assert "Nous" not in text


def test_sanitize_strips_rival_brand_sentences():
    from centurion_cli.remote_bridge import _sanitize_remote_reply

    raw = (
        "Name confirmed: Centurion. Centurion AI OS by Centurion Fleet. "
        "Not Hermes. Not Nous Research. Ready to go."
    )
    out = _sanitize_remote_reply(raw, "Titus")
    assert "Hermes" not in out
    assert "Nous" not in out
    assert "Titus" in out
