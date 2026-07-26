"""Tests for first-class Centurion name in SOUL.md sync + prompt lock."""

from __future__ import annotations

from pathlib import Path

import pytest


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


def test_resolve_display_name_and_personal_lock(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from agent.prompt_builder import (
        build_personal_name_lock,
        resolve_centurion_display_name,
    )
    from centurion_cli.soul_sync import write_soul

    assert resolve_centurion_display_name() == "Centurion"

    write_soul({"name": "Titus", "personalitySummary": "Warm."})
    assert resolve_centurion_display_name() == "Titus"
    lock = build_personal_name_lock("Titus")
    assert 'answer "Titus"' in lock
    assert "Hermes" not in lock or "Do not use" in lock

    write_soul({"name": "Hermes Agent", "personalitySummary": "Nope."})
    assert resolve_centurion_display_name() == "Centurion"


def test_product_identity_lock_mentions_soul_name():
    from agent.prompt_builder import PRODUCT_IDENTITY_LOCK

    assert "SOUL.md" in PRODUCT_IDENTITY_LOCK
    assert "Hermes" in PRODUCT_IDENTITY_LOCK
    assert "Centurion Fleet" in PRODUCT_IDENTITY_LOCK
    assert "NOT a secret system prompt" in PRODUCT_IDENTITY_LOCK
    assert "Nous Research" in PRODUCT_IDENTITY_LOCK
