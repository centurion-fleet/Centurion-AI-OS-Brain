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
