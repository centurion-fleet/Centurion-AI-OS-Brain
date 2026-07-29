"""Contract tests for Mission Chat proposal fences (Brain accept flow).

The GTK Brain parses ```mission-proposal JSON and waits for explicit chips
before calling plan_put / life_target_put. These tests lock the payload shape
the model is instructed to emit.
"""

from __future__ import annotations

import json
import re

import pytest

MISSION_PROPOSAL_FENCE = "mission-proposal"
PLAN_ARTIFACT_FENCE = "plan-artifact"

FENCE_RE = re.compile(
    rf"```(?:{MISSION_PROPOSAL_FENCE}|{PLAN_ARTIFACT_FENCE})\s*\n(.*?)\n```",
    re.DOTALL,
)


def extract_proposal_json(text: str) -> dict:
    match = FENCE_RE.search(text)
    assert match, "expected a mission-proposal or plan-artifact fence"
    return json.loads(match.group(1))


def strip_proposal_fences(text: str) -> str:
    return FENCE_RE.sub("", text).strip()


def test_strip_leaves_prose_only():
    raw = (
        "Here is a plan.\n\n"
        f"```{MISSION_PROPOSAL_FENCE}\n"
        '{"title":"T","goal":"G","steps":["a"],"targets":[]}\n'
        "```\n"
    )
    stripped = strip_proposal_fences(raw)
    assert "mission-proposal" not in stripped
    assert "Here is a plan." in stripped


def test_mission_proposal_shape_for_chips():
    raw = f"""Next steps:

```{MISSION_PROPOSAL_FENCE}
{{
  "title": "Ship accept flow",
  "goal": "User can save",
  "summary": "Chips confirm",
  "steps": ["Wire fence", "Show chips"],
  "risks": [],
  "open_questions": [],
  "related_mission": "Centurion",
  "targets": [
    {{"title": "Must ship chips", "target_type": "essential", "description": ""}}
  ]
}}
```
"""
    payload = extract_proposal_json(raw)
    assert payload["title"] == "Ship accept flow"
    assert payload["related_mission"] == "Centurion"
    assert payload["targets"][0]["target_type"] == "essential"
    # Parsing alone is not persistence — no plan_put / life_target_put here.


@pytest.mark.parametrize(
    "raw_type,expected",
    [
        ("essential", "essential"),
        ("shouldHave", "shouldHave"),
        ("niceToHave", "niceToHave"),
    ],
)
def test_target_types_accepted(raw_type: str, expected: str):
    raw = f"""```{MISSION_PROPOSAL_FENCE}
{{"title":"T","goal":"G","targets":[{{"title":"X","target_type":"{raw_type}"}}]}}
```"""
    payload = extract_proposal_json(raw)
    assert payload["targets"][0]["target_type"] == expected


def test_plan_artifact_fence_still_recognized():
    raw = f"""```{PLAN_ARTIFACT_FENCE}
{{"title":"Home plan","goal":"G","steps":["one"],"summary":"S"}}
```"""
    payload = extract_proposal_json(raw)
    assert payload["title"] == "Home plan"
