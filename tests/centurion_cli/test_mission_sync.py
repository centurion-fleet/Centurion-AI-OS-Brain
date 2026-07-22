"""Tests for Life Mission sync → LIFE_MISSION.md + USER.md + guidance."""

from __future__ import annotations

import pytest

from centurion_cli.mission_sync import (
    build_mission_guidance,
    markdown_to_structured,
    structured_to_markdown,
    upsert_user_md_mission,
    user_md_path,
    write_mission,
)
from centurion_cli.remote_bridge import handle_request


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text("agent:\n  autonomy_level: balanced\n", encoding="utf-8")
    return home


def test_mission_structured_round_trip(centurion_home):
    fields = {
        "id": "11111111-1111-1111-1111-111111111111",
        "statement": "Build Australia's leading OEM lighting towers.",
        "targets": [
            {"id": "22222222-2222-2222-2222-222222222222", "title": "Ship Remote", "description": "Owners on iPhone"},
        ],
        "profile": {
            "whyThisMission": "Local craftsmanship.",
            "yourValues": ["Reliability", "Directness"],
            "yourStory": "Founder story.",
        },
    }
    md = structured_to_markdown(fields)
    assert "centurion:mission-structured:begin" in md
    parsed = markdown_to_structured(md)
    assert parsed["statement"].startswith("Build Australia")
    assert parsed["profile"]["yourValues"] == ["Reliability", "Directness"]
    assert parsed["targets"][0]["title"] == "Ship Remote"


def test_write_mission_updates_user_md(centurion_home):
    # Pre-seed unrelated USER entry
    path = user_md_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("Prefers short answers\n", encoding="utf-8")

    result = write_mission(
        {
            "statement": "Advance the Life Mission.",
            "targets": [{"title": "Close App Store", "description": "Submit 5.0.1"}],
            "profile": {"yourValues": ["Clarity"]},
        }
    )
    assert result["exists"] is True
    assert result["statement"] == "Advance the Life Mission."

    raw = path.read_text(encoding="utf-8")
    assert "Prefers short answers" in raw
    assert "centurion:life-mission-user" in raw
    assert "Advance the Life Mission." in raw

    # Second write replaces managed entry once
    write_mission({"statement": "Updated mission.", "profile": {}, "targets": []})
    raw2 = path.read_text(encoding="utf-8")
    assert raw2.count("centurion:life-mission-user") == 1
    assert "Updated mission." in raw2
    assert "Prefers short answers" in raw2


def test_mission_guidance_shapes_prompt(centurion_home):
    write_mission(
        {
            "statement": "Own the mission north star.",
            "profile": {"whyThisMission": "Because it matters.", "yourValues": ["Courage"]},
            "targets": [{"title": "Ship", "description": "Release"}],
        }
    )
    text = build_mission_guidance()
    assert "LIFE MISSION" in text
    assert "Own the mission north star." in text
    assert "Courage" in text
    assert "Prioritize" in text


def test_remote_bridge_mission_actions(centurion_home):
    put = handle_request(
        {
            "id": "m1",
            "action": "mission_put",
            "mission": {
                "statement": "Bridge mission.",
                "targets": [{"title": "A", "description": "B"}],
                "profile": {"yourValues": ["Truth"]},
            },
        }
    )
    assert put["ok"] is True
    assert put["mission"]["statement"] == "Bridge mission."

    got = handle_request({"id": "m2", "action": "mission_get"})
    assert got["ok"] is True
    assert got["mission"]["statement"] == "Bridge mission."


def test_upsert_preserves_unrelated(centurion_home):
    path = user_md_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("Alpha note\n§\nBeta note\n", encoding="utf-8")
    upsert_user_md_mission({"statement": "Mission X", "profile": {}, "targets": []})
    upsert_user_md_mission({"statement": "Mission Y", "profile": {}, "targets": []})
    raw = path.read_text(encoding="utf-8")
    assert "Alpha note" in raw and "Beta note" in raw
    assert raw.count("centurion:life-mission-user") == 1
    assert "Mission Y" in raw
