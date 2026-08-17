"""Tests for collaboration snapshot resolve + create board."""

from __future__ import annotations


def test_create_collaboration_board_tethers_mission(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    import agent.vault as vault_mod
    vault_mod._shared_store = None
    vault_mod._shared_embedder = None

    from centurion_cli.swarm_state import create_collaboration_board, get_swarm_snapshot

    result = create_collaboration_board(
        name="Q3 Launch",
        objective="Ship the launch kit",
        mission_id="mission-abc",
    )
    assert result["ok"] is True
    slug = result["swarm_id"]
    snapshot = get_swarm_snapshot()
    match = next(s for s in snapshot["swarms"] if s["id"] == slug)
    assert match["mission_id"] == "mission-abc"
    assert "Q3 Launch" in match["display_name"]
    assert snapshot["portal"]["ok"] is False
    assert snapshot["projects"] == []
    assert snapshot["portal"].get("source") == "local"


def test_resolve_signal_unblocks_and_receipt(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    import agent.vault as vault_mod
    vault_mod._shared_store = None
    vault_mod._shared_embedder = None

    from centurion_cli import kanban_db
    from centurion_cli.swarm_state import create_collaboration_board, resolve_signal
    from agent.vault import initialize

    initialize("test-passphrase-ok")
    created = create_collaboration_board(name="Decide Board", objective="Need a choice")
    slug = created["swarm_id"]
    conn = kanban_db.connect(board=slug)
    try:
        task_id = kanban_db.create_task(
            conn, title="Pick vendor", body="Needs your choice"
        )
        assert kanban_db.block_task(conn, task_id, reason="Waiting on human")
        signal_id = f"{slug}:{task_id}:signal"
    finally:
        conn.close()

    result = resolve_signal(signal_id, choice_note="Chose Acme")
    assert result["ok"] is True
    assert result["swarm_id"] == slug
    assert result.get("vault_entry_id")


def test_snapshot_merges_portal_when_sync_ok(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    (home / "mc.json").write_text(
        '{"project_id":"proj-1","project_token":"ctk_proj_abc","install_id":"inst-1"}',
        encoding="utf-8",
    )

    class _FakeClient:
        def __init__(self, **kwargs):
            pass

        def sync(self, project_id, since=None):
            return {
                "projects": [
                    {
                        "id": project_id,
                        "title": "Shared board",
                        "status": "active",
                        "sprint_phase": "execute",
                    }
                ],
                "targets": [],
                "tasks": [],
            }

    monkeypatch.setattr("gateway.swarm_mc.SwarmMcClient", _FakeClient)
    from centurion_cli.swarm_state import get_swarm_snapshot

    snap = get_swarm_snapshot()
    assert snap["portal"]["ok"] is True
    assert any(p.get("id") == "proj-1" for p in snap["projects"])
    assert any(s.get("id") == "proj-1" for s in snap["swarms"])
