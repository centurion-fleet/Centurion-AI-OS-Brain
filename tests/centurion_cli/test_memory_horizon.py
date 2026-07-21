"""Hermetic tests for Memory Horizon snapshot + remote_bridge action."""

from __future__ import annotations

from pathlib import Path

import pytest

from centurion_cli.memory_horizon import (
    DEFAULT_MEMORY_CHAR_LIMIT,
    DEFAULT_USER_CHAR_LIMIT,
    _fill_ratio,
    _hot_cache_fill,
    build_memory_horizon_snapshot,
)
from centurion_cli.remote_bridge import handle_request


@pytest.fixture
def centurion_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "config.yaml").write_text(
        "memory:\n  memory_char_limit: 2200\n  user_char_limit: 1375\n"
        "vault:\n  enabled: false\n",
        encoding="utf-8",
    )
    return home


def test_fill_ratio_helpers():
    assert _fill_ratio(0, 100) == 0.0
    assert _fill_ratio(25, 75) == 0.25
    assert _fill_ratio(100, 0) == 1.0
    assert _hot_cache_fill(0, 3575) == 0.0
    assert _hot_cache_fill(3575, 3575) == 1.0
    assert _hot_cache_fill(7000, 3575) == 1.0


def test_build_memory_horizon_snapshot_hot_cache(centurion_home, monkeypatch):
    mem_dir = centurion_home / "memories"
    mem_dir.mkdir()
    (mem_dir / "MEMORY.md").write_text("A" * 100, encoding="utf-8")
    (mem_dir / "USER.md").write_text("B" * 50, encoding="utf-8")
    monkeypatch.setattr(
        "tools.memory_tool.get_memory_dir",
        lambda: mem_dir,
    )

    snap = build_memory_horizon_snapshot()
    hot = snap["hot_cache"]
    assert hot["memory_chars"] == 100
    assert hot["user_chars"] == 50
    assert hot["used_chars"] == 150
    assert hot["memory_limit"] == DEFAULT_MEMORY_CHAR_LIMIT
    assert hot["user_limit"] == DEFAULT_USER_CHAR_LIMIT
    assert hot["limit_chars"] == DEFAULT_MEMORY_CHAR_LIMIT + DEFAULT_USER_CHAR_LIMIT
    assert 0.0 < hot["fill_ratio"] < 1.0

    recall = snap["session_recall"]
    assert recall["sessions"] >= 0
    assert recall["messages"] >= 0
    assert recall["free_bytes"] >= 0
    assert 0.0 <= recall["fill_ratio"] <= 1.0

    vault = snap["vault"]
    assert vault["enabled"] is False
    assert vault["fill_ratio"] == 0.0
    assert vault["counts"]["core"] == 0


def test_remote_bridge_memory_horizon_snapshot(centurion_home, monkeypatch):
    mem_dir = centurion_home / "memories"
    mem_dir.mkdir()
    (mem_dir / "MEMORY.md").write_text("hello memory", encoding="utf-8")
    (mem_dir / "USER.md").write_text("hello user", encoding="utf-8")
    monkeypatch.setattr(
        "tools.memory_tool.get_memory_dir",
        lambda: mem_dir,
    )

    got = handle_request({"id": "mh1", "action": "memory_horizon_snapshot"})
    assert got["ok"] is True
    assert got["action"] == "memory_horizon_snapshot"
    snap = got["snapshot"]
    assert snap["hot_cache"]["used_chars"] == len("hello memory") + len("hello user")
    assert "session_recall" in snap
    assert "vault" in snap
    assert isinstance(snap["vault"]["counts"], dict)
