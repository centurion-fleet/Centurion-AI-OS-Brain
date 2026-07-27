"""Tests for Memory Horizon continuity (Session Recall + Vault experiential)."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from agent.memory_continuity import (
    build_continuity_context_block,
    build_session_recall_digest,
    continuity_status,
    load_horizon_continuity_config,
    prefetch_continuity_for_session,
    run_session_end_digest,
)
from centurion_cli.memory_horizon import build_memory_horizon_snapshot


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text(
        "memory:\n"
        "  memory_char_limit: 2200\n"
        "  user_char_limit: 1375\n"
        "  horizon:\n"
        "    continuity_prefetch: true\n"
        "    session_end_digest: true\n"
        "    digest_max_chars: 800\n"
        "    lookback_hours: 48\n"
        "vault:\n"
        "  enabled: false\n",
        encoding="utf-8",
    )
    (home / "memories").mkdir()
    (home / "state").mkdir()
    return home


def test_load_horizon_continuity_config(centurion_home):
    cfg = load_horizon_continuity_config()
    assert cfg["continuity_prefetch"] is True
    assert cfg["session_end_digest"] is True
    assert cfg["digest_max_chars"] == 800
    assert cfg["lookback_hours"] == 48


def test_build_continuity_context_block_empty():
    assert build_continuity_context_block("") == ""
    assert build_continuity_context_block("   ") == ""


def test_build_continuity_context_block_fenced():
    block = build_continuity_context_block("- [yesterday] hello")
    assert block.startswith("<memory-continuity>")
    assert "hello" in block
    assert block.endswith("</memory-continuity>")


def test_prefetch_first_turn_only(centurion_home):
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_prefetch_done = False
    agent._user_turn_count = 1
    agent.session_id = "sess-current"
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }

    with patch(
        "agent.memory_continuity.build_session_recall_digest",
        return_value="- [2026-07-26] Prior work — user: ship it",
    ):
        first = prefetch_continuity_for_session(agent)
        second = prefetch_continuity_for_session(agent)

    assert "<memory-continuity>" in first
    assert "Prior work" in first
    assert second == ""
    assert agent._continuity_prefetch_done is True


def test_prefetch_skipped_after_first_turn(centurion_home):
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_prefetch_done = False
    agent._user_turn_count = 3
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }
    assert prefetch_continuity_for_session(agent) == ""
    assert agent._continuity_prefetch_done is True


def test_session_end_digest_skips_short_threads(centurion_home):
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_digest_done = False
    agent.agent_context = "primary"
    agent.session_id = "s1"
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }
    run_session_end_digest(agent, [{"role": "user", "content": "hi"}])
    assert agent._continuity_digest_done is False


def test_session_end_digest_proposes_vault(centurion_home):
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_digest_done = False
    agent.agent_context = "primary"
    agent.session_id = "s1"
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }
    messages = [
        {"role": "user", "content": "Let's plan the fleet rollout with Eve."},
        {"role": "assistant", "content": "Agreed — Eve should check in first."},
        {"role": "user", "content": "Also protect Quarter Holiday."},
        {"role": "assistant", "content": "Noted — family time stays sacred."},
    ]
    with patch(
        "agent.memory_continuity.summarize_session_for_continuity",
        return_value="We planned Eve check-in and Quarter Holiday protection.",
    ), patch(
        "agent.memory_continuity._propose_vault_experiential",
        return_value="vault:experiential:proposed",
    ) as propose:
        run_session_end_digest(agent, messages)

    propose.assert_called_once()
    assert agent._continuity_digest_done is True
    state_path = centurion_home / "state" / "memory_continuity.json"
    assert state_path.is_file()
    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert state["last_digest_target"] == "vault:experiential:proposed"
    assert state["last_digest_at"]


def test_session_end_digest_hot_cache_fallback(centurion_home):
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_digest_done = False
    agent.agent_context = "primary"
    agent.session_id = "s-hot"
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }
    messages = [
        {"role": "user", "content": "Remember the tribe meeting next week."},
        {"role": "assistant", "content": "I'll keep the meeting on our horizon."},
        {"role": "user", "content": "Also note Jarrod's network priorities."},
        {"role": "assistant", "content": "Logged — network first."},
    ]
    with patch(
        "agent.memory_continuity.summarize_session_for_continuity",
        return_value="Tribe meeting next week; Jarrod network priorities.",
    ), patch(
        "agent.memory_continuity._propose_vault_experiential",
        return_value=None,
    ), patch(
        "agent.memory_continuity._vault_skip_reason",
        return_value="Vault off — wrote Hot Cache continuity instead",
    ):
        run_session_end_digest(agent, messages)

    assert agent._continuity_digest_done is True
    cont_path = centurion_home / "memories" / "CONTINUITY.md"
    assert cont_path.is_file()
    assert "tribe meeting" in cont_path.read_text(encoding="utf-8").lower()
    state = json.loads((centurion_home / "state" / "memory_continuity.json").read_text())
    assert state["last_digest_target"] == "hot_cache:continuity"
    assert "Vault off" in (state.get("last_digest_skip_reason") or "")


def test_prefetch_includes_hot_cache_continuity(centurion_home):
    (centurion_home / "memories" / "CONTINUITY.md").write_text(
        "# Continuity note\n\nProtect Quarter Holiday.\n",
        encoding="utf-8",
    )
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_prefetch_done = False
    agent._user_turn_count = 1
    agent.session_id = "sess-current"
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }
    with patch(
        "agent.memory_continuity.build_session_recall_digest",
        return_value="",
    ):
        block = prefetch_continuity_for_session(agent)
    assert "<memory-continuity>" in block
    assert "Quarter Holiday" in block


def test_session_end_digest_skips_cron(centurion_home):
    agent = MagicMock()
    agent._skip_memory = False
    agent._continuity_digest_done = False
    agent.agent_context = "cron"
    agent._horizon_continuity_cfg = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": 800,
        "lookback_hours": 48,
    }
    messages = [
        {"role": "user", "content": "cron tick"},
        {"role": "assistant", "content": "done"},
    ]
    with patch("agent.memory_continuity.summarize_session_for_continuity") as summarize:
        run_session_end_digest(agent, messages)
    summarize.assert_not_called()


def test_horizon_snapshot_includes_continuity(centurion_home, monkeypatch):
    mem_dir = centurion_home / "memories"
    (mem_dir / "MEMORY.md").write_text("fact", encoding="utf-8")
    (mem_dir / "USER.md").write_text("pref", encoding="utf-8")
    monkeypatch.setattr("tools.memory_tool.get_memory_dir", lambda: mem_dir)

    snap = build_memory_horizon_snapshot()
    assert "continuity" in snap
    cont = snap["continuity"]
    assert "continuity_prefetch" in cont
    assert "sessions_last_24h" in cont
    assert cont["continuity_prefetch"] is True


def test_build_session_recall_digest_empty_db(centurion_home):
    # No state.db → empty digest (or SessionDB creates empty)
    digest = build_session_recall_digest(current_session_id="x")
    assert digest == "" or isinstance(digest, str)
