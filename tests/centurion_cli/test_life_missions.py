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


def test_plan_decide_writes_life_decision(life_home):
    from centurion_cli.life_missions import list_decisions, put_mission
    from centurion_cli.plans import put_plan
    from centurion_cli.remote_bridge import handle_request

    mission = put_mission(
        {
            "title": "Ship product",
            "statement": "Ship product",
            "mission_type": "primary",
            "targets": [{"title": "MVP", "target_type": "essential"}],
        }
    )
    plan = put_plan(
        {
            "title": "Launch checklist",
            "goal": "Ship v1",
            "steps": ["Build", "Ship"],
            "status": "pending_review",
            "related_mission": mission["id"],
        }
    )
    plan_id = plan.get("id") if isinstance(plan, dict) else plan
    resp = handle_request(
        {
            "id": "t1",
            "action": "plan_decide",
            "plan_id": str(plan_id),
            "choice": "approve",
            "note": "Go with the amber colour direction",
        }
    )
    assert resp["ok"] is True
    decisions = list_decisions(limit=10)
    assert decisions
    assert any("amber" in (d.get("human_said") or "").lower() for d in decisions)
    assert any("Approved" in (d.get("chosen") or "") for d in decisions)


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


def test_put_list_document_resolve_inject(life_home):
    from centurion_cli.life_missions import (
        get_document,
        inject_context,
        list_documents,
        list_thoughts,
        put_document,
        put_mission,
        resolve_context,
        set_primary,
    )

    mission = put_mission(
        {
            "title": "Cashflow clarity",
            "statement": "Know where money goes",
            "mission_type": "primary",
            "targets": [{"title": "Map accounts", "target_type": "essential"}],
        }
    )
    set_primary(mission["id"])
    doc = put_document(
        {
            "mission_id": mission["id"],
            "title": "Q3 cashflow research",
            "doc_type": "research",
            "summary": "Burn and runway snapshot",
            "body_md": "# Research\n\nMonthly burn is high; runway ~8 months.",
            "source": "agent",
        }
    )
    assert doc["id"]
    assert doc["doc_type"] == "research"
    assert get_document(doc["id"])["title"] == "Q3 cashflow research"
    listed = list_documents(mission_id=mission["id"])
    assert any(d["id"] == doc["id"] for d in listed)

    # Real save pulses the thought stream (TV / Focus activity).
    thoughts = list_thoughts(limit=10)
    assert any(
        "Q3 cashflow research" in (t.get("summary") or "")
        and t.get("activity_type") == "artifact"
        for t in thoughts
    )

    # Omitting mission_id falls back to Primary.
    doc2 = put_document(
        {
            "title": "Primary default memo",
            "body_md": "Landed on primary without mission_id.",
            "doc_type": "content",
            "announce": False,
        }
    )
    assert doc2["mission_id"] == mission["id"]

    updated = put_document(
        {
            "id": doc["id"],
            "mission_id": mission["id"],
            "title": "Q3 cashflow research",
            "doc_type": "analysis",
            "summary": "Revised burn analysis",
            "body_md": "# Analysis\n\nCut burn by 15%.",
            "source": "agent",
            "announce": False,
        }
    )
    assert updated["doc_type"] == "analysis"

    matches = resolve_context("cashflow research")
    assert matches
    assert any(
        (m.get("document") or {}).get("id") == doc["id"]
        or (m.get("mission") or {}).get("id") == mission["id"]
        for m in matches
    )

    injected = inject_context(
        "summarise our cashflow work",
        current_view={
            "mission_id": mission["id"],
            "document_ids": [doc["id"]],
        },
    )
    text = injected["formatted_for_ai"].lower()
    assert "available documents" in text
    assert "cashflow" in text
    docs = injected["resolved_context"]["documents"]
    assert docs
    assert docs[0]["id"] == doc["id"]


def test_bridge_life_document_actions(life_home):
    from centurion_cli.life_missions import put_mission
    from centurion_cli.remote_bridge import handle_request

    mission = put_mission(
        {
            "title": "Content sprint",
            "statement": "Ship newsletter",
            "mission_type": "supporting",
        }
    )

    def call(action, **kwargs):
        return handle_request({"id": "doc1", "action": action, **kwargs})

    r = call(
        "life_document_put",
        document={
            "mission_id": mission["id"],
            "title": "Draft outline",
            "doc_type": "content",
            "body_md": "Intro, body, CTA",
            "source": "user",
        },
    )
    assert r["ok"] is True
    doc_id = r["document"]["id"]

    r = call("life_documents_list", mission_id=mission["id"])
    assert r["ok"] is True
    assert any(d["id"] == doc_id for d in r["documents"])

    r = call("life_document_get", document_id=doc_id)
    assert r["ok"] is True
    assert r["document"]["title"] == "Draft outline"


def test_life_missions_tool_put_document(life_home):
    import json

    from centurion_cli.life_missions import put_mission
    from tools.life_missions_tool import life_missions_tool

    mission = put_mission(
        {
            "title": "Report mission",
            "statement": "Write the weekly report",
            "mission_type": "primary",
        }
    )
    raw = life_missions_tool(
        action="put_document",
        mission_id=mission["id"],
        title="Weekly report",
        summary="Ops summary",
        fields_json=json.dumps(
            {
                "doc_type": "report",
                "body_md": "## Wins\n\nShipped Focus documents.",
                "source": "agent",
            }
        ),
    )
    data = json.loads(raw)
    assert data["success"] is True
    assert data["document"]["doc_type"] == "report"
    assert data["document"]["mission_id"] == mission["id"]

    listed = json.loads(
        life_missions_tool(action="list_documents", mission_id=mission["id"])
    )
    assert listed["success"] is True
    assert any(d["title"] == "Weekly report" for d in listed["documents"])


def test_search_documents_body_title_agent_filter(life_home):
    from centurion_cli.life_missions import (
        put_document,
        put_mission,
        resolve_context,
        search_documents,
        set_primary,
    )
    from centurion_cli.remote_bridge import handle_request

    m1 = put_mission(
        {
            "title": "Swarm Mode",
            "statement": "Raise capital",
            "mission_type": "primary",
        }
    )
    m2 = put_mission(
        {
            "title": "Side quest",
            "statement": "Other work",
            "mission_type": "supporting",
        }
    )
    set_primary(m1["id"])
    put_document(
        {
            "mission_id": m1["id"],
            "title": "Investment memorandum",
            "doc_type": "report",
            "summary": "Term sheet overview",
            "body_md": "UniquePhraseXYZ runway and valuation for Swarm Mode.",
            "source": "agent",
            "announce": False,
        }
    )
    put_document(
        {
            "mission_id": m2["id"],
            "title": "User notes",
            "body_md": "UniquePhraseXYZ but from a human.",
            "source": "user",
            "announce": False,
        }
    )

    by_body = search_documents("UniquePhraseXYZ")
    assert len(by_body) >= 2
    assert any(d.get("mission_title") for d in by_body)

    agent_only = search_documents("UniquePhraseXYZ", source="agent")
    assert len(agent_only) == 1
    assert agent_only[0]["title"] == "Investment memorandum"
    assert agent_only[0]["source"] == "agent"

    scoped = search_documents("memorandum", mission_id=m1["id"])
    assert len(scoped) == 1
    assert scoped[0]["mission_id"] == m1["id"]

    matches = resolve_context("UniquePhraseXYZ valuation")
    assert any((m.get("document") or {}).get("title") == "Investment memorandum" for m in matches)

    resp = handle_request(
        {
            "id": "s1",
            "action": "life_documents_search",
            "query": "Investment",
            "source": "agent",
        }
    )
    assert resp["ok"] is True
    assert any(d["title"] == "Investment memorandum" for d in resp["documents"])


def test_import_scanned_documents_files_plans_idempotent(life_home, tmp_path):
    from centurion_cli.life_missions import (
        DOCUMENT_LIBRARY_MISSION_ID,
        get_document,
        import_scanned_documents,
        list_documents,
        put_mission,
        search_documents,
        set_primary,
    )
    from centurion_cli.plans import put_plan
    from centurion_cli.remote_bridge import handle_request

    primary = put_mission(
        {
            "title": "Isaac Primary",
            "statement": "Sail the planet",
            "mission_type": "primary",
        }
    )
    supporting = put_mission(
        {
            "title": "Centurion AI Limited",
            "statement": "Scale the business",
            "mission_type": "supporting",
        }
    )
    set_primary(primary["id"])

    docs_dir = tmp_path / "Documents"
    docs_dir.mkdir()
    # Path contains supporting mission title so import prefers it over Primary.
    nested = docs_dir / "Centurion AI Limited" / "memos"
    nested.mkdir(parents=True)
    memo = nested / "investment-research.md"
    memo.write_text(
        "# Memo\n\nUniqueImportPhraseABC for Centurion AI Limited scale.\n",
        encoding="utf-8",
    )

    plan = put_plan(
        {
            "title": "Go-to-market plan",
            "goal": "Win first customers",
            "summary": "Outbound sequence",
            "steps": ["List accounts", "Draft outreach"],
            "status": "pending_review",
        }
    )

    result = import_scanned_documents(
        roots=[docs_dir],
        mission_id=primary["id"],
        include_plans=True,
        include_outcomes=False,
    )
    assert result["imported"] >= 2
    assert result["scanned_files"] >= 1

    hits = search_documents("UniqueImportPhraseABC")
    assert len(hits) == 1
    assert hits[0]["source"] == "import"
    assert hits[0]["mission_id"] == supporting["id"]
    assert "Imported from:" in (hits[0].get("summary") or "")

    # Primary must not inherit the whole scan — only title-matched missions.
    primary_docs = list_documents(mission_id=primary["id"], limit=50)
    assert all(
        "UniqueImportPhraseABC" not in (d.get("body_md") or "") for d in primary_docs
    )

    plan_docs = [
        d for d in list_documents(limit=50) if d.get("plan_id") == plan["id"]
    ]
    assert len(plan_docs) == 1
    assert plan_docs[0]["doc_type"] == "plan"
    # Unmatched plans land in Document library, not Primary.
    assert plan_docs[0]["mission_id"] == DOCUMENT_LIBRARY_MISSION_ID

    first_id = hits[0]["id"]
    again = import_scanned_documents(
        roots=[docs_dir],
        mission_id=primary["id"],
        include_plans=True,
        include_outcomes=False,
    )
    assert again["imported"] == 0
    assert again["updated"] >= 1
    assert get_document(first_id) is not None
    assert len(search_documents("UniqueImportPhraseABC")) == 1

    resp = handle_request(
        {
            "id": "imp1",
            "action": "life_documents_import_scan",
            "path": str(docs_dir),
            "include_plans": False,
            "include_outcomes": False,
        }
    )
    assert resp["ok"] is True
    assert resp["updated"] >= 1


def test_life_bridge_errors_are_not_thinking_recovery_copy(life_home):
    """Focus Scan failures must show the real fault, not LKG recovery copy."""
    from centurion_cli.remote_bridge import handle_request

    # Force a failure inside the import handler by asking for a nonsense path
    # that still returns ok:true with soft errors — and a missing function path
    # via a deliberately bad nested call isn't needed. Probe unsupported first.
    unsupported = handle_request(
        {"id": "u1", "action": "life_documents_import_scan_typo"}
    )
    assert unsupported["ok"] is False
    assert unsupported["code"] == "UNSUPPORTED_ACTION"
    assert "restore your last working setup" not in (
        unsupported.get("message") or ""
    ).lower()

    # Real action with no missions yet → soft result (never thinking recovery).
    resp = handle_request(
        {
            "id": "imp2",
            "action": "life_documents_import_scan",
            "path": str(life_home / "missing-docs-dir"),
            "include_plans": False,
            "include_outcomes": False,
        }
    )
    assert resp["ok"] is True
    assert "restore your last working setup" not in str(resp).lower()
    assert resp.get("imported", 0) == 0
