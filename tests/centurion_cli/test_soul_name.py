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
