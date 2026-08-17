"""Offline Missions / Plans tools — no portal token required."""

from __future__ import annotations

import json

import pytest

from centurion_cli.remote_bridge import handle_request


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text("agent:\n  autonomy_level: balanced\n", encoding="utf-8")
    return home


def test_plans_tool_put_list_no_token(centurion_home):
    from tools.plans_tool import plans_tool

    created = json.loads(
        plans_tool(
            action="put",
            title="Cashflow sprint",
            goal="Generate consistent savings",
            fields_json=json.dumps(
                {
                    "steps": ["Map revenue", "Cut waste", "Automate invoice"],
                    "risks": ["Overcommitment"],
                }
            ),
        )
    )
    assert created["success"] is True
    assert created["plan"]["title"] == "Cashflow sprint"
    assert created["plan"]["id"]

    listed = json.loads(plans_tool(action="list", status="proposed"))
    assert listed["success"] is True
    assert any(p["id"] == created["plan"]["id"] for p in listed["plans"])


def test_mission_control_tool_refuses_portal(centurion_home):
    import asyncio

    from tools.mission_control_tool import handle_mission_control

    out = asyncio.get_event_loop().run_until_complete(
        handle_mission_control({"action": "sync"})
    )
    data = json.loads(out) if out.strip().startswith("{") else {"error": out}
    blob = json.dumps(data).lower() + out.lower()
    assert "frozen" in blob or "life_missions" in blob
    assert "ctk_proj" in blob or "portal" in blob


def test_swarm_connect_requires_token(centurion_home):
    resp = handle_request(
        {
            "id": "1",
            "action": "swarm_connect",
            "token": "not-a-project-token",
            "project_id": "proj",
            "install_id": "inst",
        }
    )
    assert resp["ok"] is False
    assert resp.get("code") == "MC_TOKEN_REQUIRED"


def test_swarm_snapshot_local_only(centurion_home):
    from centurion_cli.swarm_state import create_collaboration_board, get_swarm_snapshot

    create_collaboration_board(name="Desk", objective="Local only")
    snap = get_swarm_snapshot()
    assert snap["ok"] is True
    assert snap["portal"]["ok"] is False
    assert snap["projects"] == []
    assert any("Desk" in s.get("display_name", "") for s in snap["swarms"])


def test_life_missions_create_supporting_no_token(centurion_home):
    from tools.life_missions_tool import life_missions_tool

    out = json.loads(
        life_missions_tool(
            action="create_mission",
            title="Cash flow",
            statement="Generate consistent cash flow and savings",
            fields_json=json.dumps({"mission_type": "supporting"}),
        )
    )
    assert out["success"] is True
    assert out["mission"]["mission_type"] == "supporting"
    assert "portal" not in json.dumps(out).lower()


def test_guidance_prefers_life_stack(centurion_home):
    from centurion_cli.life_missions import put_mission
    from centurion_cli.mission_sync import build_mission_guidance
    from agent.prompt_builder import LIFE_MISSIONS_GUIDANCE, PLANS_GUIDANCE

    put_mission(
        {
            "title": "Primary north star",
            "statement": "Fund the life through businesses",
            "mission_type": "primary",
            "why": "Freedom",
            "profile": {"yourValues": ["Clarity"]},
            "targets": [
                {
                    "title": "Map revenue",
                    "description": "List all streams",
                    "target_type": "essential",
                }
            ],
        }
    )
    text = build_mission_guidance()
    assert "LIFE MISSION STACK" in text
    assert "Fund the life through businesses" in text
    assert "Map revenue" in text
    assert "life_missions" in text.lower() or "life.db" in text.lower()
    assert "portal" in LIFE_MISSIONS_GUIDANCE.lower()
    assert "plans tool" in PLANS_GUIDANCE.lower()
