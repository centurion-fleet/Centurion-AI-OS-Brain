"""Hermetic tests for offline life_missions store."""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture
def life_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    return home


def test_schema_seeds_uncategorised(life_home):
    from centurion_cli.life_missions import ensure_schema, list_subjects

    ensure_schema()
    subjects = list_subjects()
    assert any(s["name"] == "Uncategorised" for s in subjects)
    assert (life_home / "life" / "life.db").exists()


def test_bootstrap_from_markdown(life_home):
    from centurion_cli import mission_sync
    from centurion_cli.life_missions import get_stack, list_missions

    mission_sync.write_mission(
        {
            "statement": "Ship the Brain offline",
            "targets": [
                {"title": "Schema", "description": "life.db"},
                {"title": "Bridge", "description": "remote actions"},
            ],
            "profile": {"whyThisMission": "Own your data"},
        }
    )
    stack = get_stack()
    assert stack["primary"] is not None
    assert stack["primary"]["statement"] == "Ship the Brain offline"
    assert len(stack["primary"]["targets"]) == 2
    assert list_missions()


def test_subject_dream_promote_primary_targets_focus_context(life_home):
    from centurion_cli.life_missions import (
        get_stack,
        inject_context,
        list_dreams,
        put_dream,
        put_mission,
        put_subject,
        put_target,
        promote_dream,
        resolve_context,
        set_primary,
    )

    subject = put_subject({"name": "Health", "icon": "heart"})
    dream = put_dream({"title": "Run a marathon", "description": "Finish under 4h"})
    assert dream["title"] == "Run a marathon"
    assert len(list_dreams()) == 1

    promoted = promote_dream(dream["id"], subject_id=subject["id"])
    mission = promoted["mission"]
    assert mission["title"] == "Run a marathon"
    assert mission["subject_id"] == subject["id"]
    assert len(list_dreams()) == 0

    mission = put_mission(
        {
            "id": mission["id"],
            "subject_id": subject["id"],
            "title": "Run a marathon",
            "statement": "Complete a marathon",
            "situation": "Training starts now",
            "why": "Prove discipline",
            "purpose": "Finish under 4 hours",
            "phase": "planning",
            "mission_type": "supporting",
            "targets": [
                {
                    "title": "Base miles",
                    "target_type": "essential",
                    "sequence_number": 1,
                },
                {
                    "title": "Long run Sundays",
                    "target_type": "shouldHave",
                    "sequence_number": 2,
                },
                {
                    "title": "Race photo",
                    "target_type": "niceToHave",
                    "sequence_number": 3,
                },
            ],
        }
    )
    assert mission["target_count"] == 3
    focus = next(t for t in mission["targets"] if t["focus_target"])
    assert focus["title"] == "Base miles"

    set_primary(mission["id"])
    stack = get_stack()
    assert stack["primary"]["id"] == mission["id"]

    put_target(
        {
            "id": focus["id"],
            "mission_id": mission["id"],
            "title": "Base miles",
            "status": "complete",
            "target_type": "essential",
            "sequence_number": 1,
        }
    )
    from centurion_cli.life_missions import get_mission

    updated = get_mission(mission["id"])
    assert updated is not None
    new_focus = next(t for t in updated["targets"] if t["focus_target"])
    assert new_focus["title"] == "Long run Sundays"

    matches = resolve_context("marathon base")
    assert matches
    injected = inject_context(
        "how's my marathon?",
        current_view={"mission_id": mission["id"]},
    )
    assert "Marathon" in injected["formatted_for_ai"] or "marathon" in injected[
        "formatted_for_ai"
    ].lower()
    assert injected["resolved_context"]["mission"]["id"] == mission["id"]


def test_legacy_mission_get_put(life_home):
    from centurion_cli.life_missions import legacy_mission_get, legacy_mission_put

    out = legacy_mission_put(
        {
            "statement": "Legacy path still works",
            "targets": [{"title": "One"}],
            "profile": {"whyThisMission": "compat"},
        }
    )
    assert out["statement"] == "Legacy path still works"
    assert out["exists"] is True
    again = legacy_mission_get()
    assert again["statement"] == "Legacy path still works"
    assert again["life"]["mission_type"] == "primary"


def test_bridge_life_actions(life_home):
    from centurion_cli.remote_bridge import handle_request

    def call(action, **kwargs):
        req = {"id": "t1", "action": action, **kwargs}
        return handle_request(req)

    r = call("life_subject_put", name="Work", icon="briefcase")
    assert r["ok"] is True
    subject_id = r["subject"]["id"]

    r = call("life_dream_put", title="Launch product", description="v1")
    assert r["ok"] is True
    dream_id = r["dream"]["id"]

    r = call("life_dream_promote", dream_id=dream_id, subject_id=subject_id)
    assert r["ok"] is True
    mission_id = r["mission"]["id"]

    r = call(
        "life_mission_put",
        mission={
            "id": mission_id,
            "subject_id": subject_id,
            "title": "Launch product",
            "statement": "Ship v1",
            "mission_type": "primary",
            "phase": "executing",
            "targets": [
                {"title": "MVP", "target_type": "essential"},
                {"title": "Docs", "target_type": "shouldHave"},
            ],
        },
    )
    assert r["ok"] is True
    assert r["mission"]["target_count"] == 2

    r = call("life_stack_get")
    assert r["ok"] is True
    assert r["stack"]["primary"]["id"] == mission_id

    r = call("life_context_inject", message="ship MVP", mission_id=mission_id)
    assert r["ok"] is True
    assert "formatted_for_ai" in r

    r = call("mission_get")
    assert r["ok"] is True
    assert r["mission"]["statement"] == "Ship v1"

    r = call("life_snapshot")
    assert r["ok"] is True
    assert "subjects" in r["snapshot"]
    assert "mission_stack" in r["snapshot"]
