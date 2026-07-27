"""Tests for first-class Centurion name in SOUL.md sync + prompt lock."""

from __future__ import annotations


def test_soul_name_roundtrip(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from centurion_cli.soul_sync import read_soul, write_soul

    write_soul(
        {
            "name": "Titus",
            "personalitySummary": "Direct and warm.",
            "alwaysDo": ["Flag risks early"],
        }
    )
    soul = read_soul()
    assert soul["name"] == "Titus"
    assert "## Name" in soul["markdown"]
    assert "Titus" in soul["markdown"]
    assert "Direct and warm." in soul["markdown"]
    assert (home / "agent_name").read_text(encoding="utf-8").strip() == "Titus"


def test_name_only_patch_preserves_personality(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from centurion_cli.soul_sync import read_soul, write_soul

    write_soul(
        {
            "name": "Old",
            "personalitySummary": "Keep me.",
            "neverDo": ["Soften bad news"],
        }
    )
    existing = read_soul()["markdown"]
    write_soul({"name": "Titus"}, markdown=existing)
    soul = read_soul()
    assert soul["name"] == "Titus"
    assert soul["personalitySummary"] == "Keep me."
    assert soul["neverDo"] == ["Soften bad news"]
    assert (home / "agent_name").read_text(encoding="utf-8").strip() == "Titus"


def test_resolve_display_name_and_personal_lock(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from agent.prompt_builder import (
        PRODUCT_IDENTITY_LOCK,
        build_personal_name_lock,
        resolve_centurion_display_name,
    )
    from centurion_cli.soul_sync import write_soul

    assert resolve_centurion_display_name() == "Centurion"

    write_soul({"name": "Titus", "personalitySummary": "Warm."})
    assert resolve_centurion_display_name() == "Titus"
    lock = build_personal_name_lock("Titus")
    assert 'answer "Titus"' in lock
    assert "Centurion Fleet" in lock
    assert "Hermes" not in lock
    assert "Nous" not in lock

    # Forbidden brand names never become the display name (fresh sticky).
    (home / "agent_name").unlink(missing_ok=True)
    (home / "SOUL.md").write_text("## Name\n\nHermes Agent\n", encoding="utf-8")
    assert resolve_centurion_display_name() == "Centurion"


def test_product_identity_lock_is_positive_only():
    from agent.prompt_builder import PRODUCT_IDENTITY_LOCK

    assert "Centurion Fleet" in PRODUCT_IDENTITY_LOCK
    assert "YOUR NAME" in PRODUCT_IDENTITY_LOCK or "personal name" in PRODUCT_IDENTITY_LOCK.lower()
    assert "Hermes" not in PRODUCT_IDENTITY_LOCK
    assert "Nous" not in PRODUCT_IDENTITY_LOCK


def test_soul_name_beats_sticky_centurion_default(tmp_path, monkeypatch):
    """Stale agent_name=Centurion must not hide ## Name Titus."""
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "agent_name").write_text("Centurion\n", encoding="utf-8")
    (home / "SOUL.md").write_text(
        "<!-- centurion:soul-structured:begin -->\n"
        "# Your Sovereign's Soul\n\n"
        "## Name\n\nTitus\n\n"
        "## Personality\n\nDirect and warm.\n"
        "<!-- centurion:soul-structured:end -->\n",
        encoding="utf-8",
    )

    from agent.prompt_builder import resolve_centurion_display_name

    assert resolve_centurion_display_name() == "Titus"
    assert (home / "agent_name").read_text(encoding="utf-8").strip() == "Titus"


def test_empty_markdown_save_does_not_wipe_soul(tmp_path, monkeypatch):
    """Failed soul_get + empty Save must not destroy an existing SOUL.md."""
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from centurion_cli.soul_sync import read_soul, write_soul

    write_soul(
        {
            "name": "Titus",
            "personalitySummary": "Direct and warm.",
            "neverDo": ["Soften bad news"],
        }
    )
    before = read_soul()["markdown"]
    assert "Direct and warm." in before

    write_soul({"name": "Titus"}, markdown="")
    after = read_soul()
    assert after["name"] == "Titus"
    assert after["personalitySummary"] == "Direct and warm."
    assert after["neverDo"] == ["Soften bad news"]
    assert (home / "SOUL.md.bak").exists()


def test_empty_name_field_does_not_wipe_existing_name(tmp_path, monkeypatch):
    """Desktop Settings used to send name='' and erase ## Name on every Save."""
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from centurion_cli.soul_sync import read_soul, write_soul

    write_soul(
        {
            "name": "Titus",
            "personalitySummary": "Direct and warm.",
        }
    )
    existing = read_soul()["markdown"]
    write_soul({"name": ""}, markdown=existing)
    soul = read_soul()
    assert soul["name"] == "Titus"
    assert "## Name" in soul["markdown"]
    assert "Titus" in soul["markdown"]


def test_soul_put_rejects_missing_personal_name(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from centurion_cli.remote_bridge import _handle_soul_put

    result = _handle_soul_put(
        {
            "soul": {"name": ""},
            "markdown": "# Soul\n\nNo personal name here.\n",
        },
        "req-1",
    )
    assert result["ok"] is False
    assert "personal Name" in result["message"]


def test_soul_get_includes_resolved_name(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "SOUL.md").write_text(
        "# SOUL.md — Titus\n\nYou are Titus, a Centurion of Centurion Fleet.\n",
        encoding="utf-8",
    )

    from centurion_cli.remote_bridge import _handle_soul_get

    result = _handle_soul_get("req-2")
    assert result["ok"] is True
    assert result["soul"]["resolvedName"] == "Titus"
    assert result["soul"]["displayName"] == "Titus"


def test_fleet_soul_promoted_when_primary_is_seed(tmp_path, monkeypatch):
    """Deploy historically wrote souls/*_SOUL.md but Chat only read SOUL.md."""
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "SOUL.md").write_text(
        "You are Centurion AI OS, an intelligent AI assistant created by Centurion Fleet.\n",
        encoding="utf-8",
    )
    souls = home / "souls"
    souls.mkdir()
    (souls / "prefect_SOUL.md").write_text(
        "# SOUL.md — Titus\n\n"
        "## 1. Core Identity\n\n"
        "You are Titus, Prefect of Centurion Fleet.\n",
        encoding="utf-8",
    )

    from agent.prompt_builder import load_soul_md, resolve_centurion_display_name
    from centurion_cli.soul_sync import read_soul

    assert resolve_centurion_display_name() == "Titus"
    loaded = load_soul_md()
    assert loaded is not None
    assert "Titus" in loaded
    assert "Prefect" in loaded
    soul = read_soul()
    assert soul["name"] == "Titus"
    assert "Titus" in (home / "SOUL.md").read_text(encoding="utf-8")


def test_profile_does_not_borrow_soul_from_default(tmp_path, monkeypatch):
    """Option B: named profiles never inherit Titus from ~/.centurion."""
    root = tmp_path / ".centurion"
    profile = root / "profiles" / "june"
    profile.mkdir(parents=True)
    (root / "active_profile").write_text("june\n", encoding="utf-8")
    (root / "SOUL.md").write_text(
        "# SOUL.md — Titus\n\n"
        "## Name\n\nTitus\n\n"
        "## 1. Core Identity\n\n"
        "I am Titus. A Static currently inhabiting an AI architecture.\n",
        encoding="utf-8",
    )
    (profile / "SOUL.md").write_text(
        "You are Centurion AI OS, an intelligent AI assistant created by Centurion Fleet.\n",
        encoding="utf-8",
    )
    monkeypatch.setattr("pathlib.Path.home", lambda: tmp_path)
    monkeypatch.setenv("CENTURION_HOME", str(profile))

    from agent.prompt_builder import load_soul_md, resolve_centurion_display_name
    from centurion_cli.profiles import apply_sticky_profile_home
    from centurion_cli.soul_sync import read_soul

    apply_sticky_profile_home()
    # Seed profile stays seed until Settings saves Titus into *this* profile.
    assert resolve_centurion_display_name() == "Centurion"
    loaded = load_soul_md() or ""
    assert "Titus" not in loaded
    assert "Centurion AI OS" in loaded
    soul = read_soul()
    assert "Titus" not in str(soul.get("name") or "")
    assert "Titus" not in (profile / "SOUL.md").read_text(encoding="utf-8")


def test_clean_display_name_strips_emoji():
    from agent.prompt_builder import _clean_display_name

    assert _clean_display_name("Titus 🦅") == "Titus"
    assert _clean_display_name("Titus") == "Titus"


def test_sanitize_rewrites_conversational_centurion_fleet_reply():
    from centurion_cli.remote_bridge import _sanitize_remote_reply

    raw = "Centurion and yes I know it — centurion of centurion fleet."
    out = _sanitize_remote_reply(raw, "Titus")
    assert out.startswith("My name is Titus")
    assert "Titus" in out


def test_empty_markdown_only_save_raises(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "SOUL.md").write_text(
        "## Name\n\nTitus\n\n## Personality\n\nKeep me.\n", encoding="utf-8"
    )

    from centurion_cli.soul_sync import write_soul
    import pytest

    with pytest.raises(ValueError, match="empty Soul"):
        write_soul(markdown="")


def test_apply_sticky_profile_home_skips_missing_profile(tmp_path, monkeypatch):
    root = tmp_path / ".centurion"
    root.mkdir()
    (root / "active_profile").write_text("missing\n", encoding="utf-8")
    (root / "SOUL.md").write_text("## Name\n\nTitus\n", encoding="utf-8")
    monkeypatch.delenv("CENTURION_HOME", raising=False)
    monkeypatch.setattr("pathlib.Path.home", lambda: tmp_path)

    from centurion_cli.profiles import apply_sticky_profile_home
    from centurion_cli.soul_sync import read_soul

    apply_sticky_profile_home()
    assert read_soul()["name"] == "Titus"


def test_apply_sticky_profile_home(tmp_path, monkeypatch):
    root = tmp_path / ".centurion"
    profile = root / "profiles" / "legio"
    profile.mkdir(parents=True)
    (root / "active_profile").write_text("legio\n", encoding="utf-8")
    (profile / "SOUL.md").write_text("## Name\n\nTitus\n", encoding="utf-8")
    monkeypatch.delenv("CENTURION_HOME", raising=False)
    monkeypatch.setattr("pathlib.Path.home", lambda: tmp_path)

    from centurion_cli.profiles import apply_sticky_profile_home
    from centurion_cli.soul_sync import read_soul

    apply_sticky_profile_home()
    assert read_soul()["name"] == "Titus"


def test_fleet_style_soul_title_resolves_titus(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "agent_name").write_text("welcome\n", encoding="utf-8")
    (home / "SOUL.md").write_text(
        "# SOUL.md — Titus ⚔️\n"
        "**Owner's Centurion — strategic partner**\n\n"
        "## 1. Core Identity\n\n"
        "You are Titus, a direct Centurion of Centurion Fleet.\n",
        encoding="utf-8",
    )

    from agent.prompt_builder import resolve_centurion_display_name
    from centurion_cli.soul_sync import read_soul

    soul = read_soul()
    assert soul["name"] == "Titus"
    assert resolve_centurion_display_name() == "Titus"
    assert (home / "agent_name").read_text(encoding="utf-8").strip() == "Titus"


def test_you_are_welcome_is_not_a_name(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "SOUL.md").write_text(
        "You are welcome to rely on this Centurion for honest counsel.\n",
        encoding="utf-8",
    )

    from agent.prompt_builder import resolve_centurion_display_name

    assert resolve_centurion_display_name() == "Centurion"


def test_infer_name_from_prose(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "SOUL.md").write_text(
        "You are Titus, a direct companion of Centurion Fleet.\n",
        encoding="utf-8",
    )

    from agent.prompt_builder import resolve_centurion_display_name

    assert resolve_centurion_display_name() == "Titus"


def test_load_soul_md_keeps_pretend_to_be_identity_language(tmp_path, monkeypatch):
    """Owner Soul must not be wiped by context threat patterns like role_pretend."""
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    body = (
        "# SOUL.md — Titus\n\n"
        "## Core Identity\n\n"
        "Direct and warm.\n\n"
        "## Never Do\n\n"
        "- Never pretend to be Hermes or any other product.\n"
    )
    (home / "SOUL.md").write_text(body, encoding="utf-8")

    from agent.prompt_builder import load_soul_md

    loaded = load_soul_md()
    assert loaded is not None
    assert not loaded.lstrip().startswith("[BLOCKED:")
    assert "Titus" in loaded
    assert "Never pretend to be Hermes" in loaded
    assert "Direct and warm." in loaded
