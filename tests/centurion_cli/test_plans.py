"""Tests for host-backed Plans store and remote bridge actions."""

from __future__ import annotations

import os

import pytest

from centurion_cli.plans import (
    classify_risk,
    comment_plan,
    decide_plan,
    instantiate_template,
    list_plans,
    list_templates,
    put_plan,
    save_plan_as_template,
    share_plan,
)
from centurion_cli.remote_bridge import handle_request


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text("agent:\n  autonomy_level: balanced\n", encoding="utf-8")
    return home


def test_put_list_decide_round_trip(centurion_home):
    plan = put_plan(
        {
            "title": "Vendor outreach",
            "goal": "Draft then wait before send",
            "steps": ["Draft email", "Wait for Proceed", "Send email"],
            "risks": ["Sending before approval"],
        }
    )
    assert plan["status"] == "pending_review"
    assert plan["risk"] in {"low", "medium", "high"}
    assert plan["id"]

    listed = list_plans("proposed")
    assert any(p["id"] == plan["id"] for p in listed)

    decided = decide_plan(plan["id"], "approve")
    assert decided["status"] == "proceeded"

    held = decide_plan(plan["id"], "hold")
    assert held["status"] == "held"

    rejected = decide_plan(plan["id"], "reject", note="Not now")
    assert rejected["status"] == "rejected"
    assert rejected["outcome_summary"] == "Not now"


def test_risk_classifier(centurion_home):
    assert classify_risk(["Read the brief"]) == "low"
    assert classify_risk(["Send the email", "Publish the post"]) == "medium"
    assert classify_risk(["rm -rf /tmp/build", "production deploy"]) == "high"


def test_templates_seed_and_instantiate(centurion_home):
    templates = list_templates()
    assert len(templates) >= 4
    ids = {t["id"] for t in templates}
    assert "research-brief" in ids

    plan = instantiate_template("research-brief")
    assert plan["status"] == "pending_review"
    assert plan["template_id"] == "research-brief"
    assert plan["steps"]

    tmpl = save_plan_as_template(plan["id"], title="My research")
    assert tmpl["id"].startswith("user-")
    assert any(t["id"] == tmpl["id"] for t in list_templates())


def test_share_and_comment(centurion_home):
    plan = put_plan({"title": "Shared plan", "goal": "Review with CEO", "steps": ["Draft", "Share"]})
    shared = share_plan(plan["id"], reviewer_customer_id="cust_ceo_1", role="observer")
    reviewers = shared["share"]["reviewers"]
    assert any(r["customer_id"] == "cust_ceo_1" for r in reviewers)

    commented = comment_plan(plan["id"], "Please tighten step 2", author="ceo")
    assert commented["share"]["comments"]
    assert commented["share"]["comments"][-1]["body"] == "Please tighten step 2"

    decided = decide_plan(
        plan["id"],
        "request_changes",
        note="Add budget check",
        reviewer_customer_id="cust_ceo_1",
    )
    assert decided["status"] == "adjusted"
    assert "Add budget check" in decided["requirements"]
    rev = next(r for r in decided["share"]["reviewers"] if r["customer_id"] == "cust_ceo_1")
    assert rev["status"] == "changes_requested"


def test_remote_bridge_plan_actions(centurion_home):
    put = handle_request(
        {
            "id": "p1",
            "action": "plan_put",
            "plan": {
                "title": "Bridge plan",
                "goal": "Via remote",
                "steps": ["One", "Two"],
            },
        }
    )
    assert put["ok"] is True
    plan_id = put["plan"]["id"]

    listed = handle_request({"id": "p2", "action": "plans_list", "status": "all"})
    assert listed["ok"] is True
    assert any(p["id"] == plan_id for p in listed["plans"])

    got = handle_request({"id": "p3", "action": "plan_get", "plan_id": plan_id})
    assert got["ok"] is True
    assert got["plan"]["title"] == "Bridge plan"

    decided = handle_request(
        {
            "id": "p4",
            "action": "plan_decide",
            "plan_id": plan_id,
            "choice": "approve",
        }
    )
    assert decided["ok"] is True
    assert decided["plan"]["status"] == "proceeded"

    templates = handle_request({"id": "p5", "action": "plan_templates_list"})
    assert templates["ok"] is True
    assert len(templates["templates"]) >= 1

    inst = handle_request(
        {
            "id": "p6",
            "action": "plan_template_instantiate",
            "template_id": "safe-change",
        }
    )
    assert inst["ok"] is True
    assert inst["plan"]["template_id"] == "safe-change"

    shared = handle_request(
        {
            "id": "p7",
            "action": "plan_share",
            "plan_id": plan_id,
            "reviewer_customer_id": "cust_x",
        }
    )
    assert shared["ok"] is True

    commented = handle_request(
        {
            "id": "p8",
            "action": "plan_comment",
            "plan_id": plan_id,
            "body": "Looks good",
            "author": "owner",
        }
    )
    assert commented["ok"] is True
    assert commented["plan"]["share"]["comments"]
