"""Hermetic tests for Centurion Vault (offline sealed memory)."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest


@pytest.fixture
def vault_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    # Clear shared vault state between tests
    import agent.vault as vault_mod

    vault_mod._shared_store = None
    vault_mod._shared_embedder = None
    yield home
    if vault_mod._shared_store is not None:
        try:
            vault_mod._shared_store.close()
        except Exception:
            pass
    vault_mod._shared_store = None
    vault_mod._shared_embedder = None


def test_init_unlock_lock_roundtrip(vault_home):
    from agent.vault import initialize, open_vault
    from agent.vault.crypto import VaultAuthError

    vault = initialize("test-passphrase-ok")
    assert vault.is_unlocked
    assert (vault_home / "vault" / "vault.key.wrapped").exists()
    assert (vault_home / "vault" / "vault.db").exists()

    vault.lock()
    assert not vault.is_unlocked

    vault2 = open_vault("test-passphrase-ok")
    assert vault2.is_unlocked

    with pytest.raises(VaultAuthError):
        open_vault("wrong-passphrase!!")


def test_propose_commit_search(vault_home):
    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    prop = vault.propose(
        memory_type="core",
        text="User prefers concise answers in English.",
        rationale="Stable preference",
        tags=["prefs"],
        importance=8,
    )
    assert prop.id
    entry = vault.commit(prop.id)
    assert entry.memory_type.value == "core"

    hits = vault.search("concise English")
    assert hits
    assert any("concise" in h.text.lower() for h in hits)


def test_lock_clears_fts(vault_home):
    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    prop = vault.propose(
        memory_type="pattern",
        text="When deploying, always run the smoke suite first.",
        rationale="Recurring workflow",
    )
    vault.commit(prop.id)
    assert vault.search("smoke suite")

    vault.lock()
    with pytest.raises(Exception):
        vault.search("smoke suite")


def test_ingest_rejects_transcript_dump(vault_home):
    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    dump = "\n".join(
        [
            "User: hello",
            "Assistant: hi",
            "User: do the thing",
            "Assistant: done",
            "User: more",
            "Assistant: ok",
            "User: again",
            "Assistant: sure",
            "User: final",
            "Assistant: bye",
            "User: wait",
            "Assistant: what",
        ]
    )
    with pytest.raises(ValueError, match="transcript"):
        vault.propose(memory_type="experiential", text=dump, rationale="dump")


def test_ingest_rejects_secrets(vault_home):
    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    with pytest.raises(ValueError, match="secret"):
        vault.propose(
            memory_type="core",
            text="api_key: sk-abcdefghijklmnopqrstuvwxyz123456",
            rationale="oops",
        )


def test_skip_memory_blocks_writes(vault_home):
    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    vault.writes_allowed = False
    with pytest.raises(ValueError, match="skip_memory"):
        vault.propose(
            memory_type="core",
            text="Should not store",
            rationale="blocked",
        )


def test_dedupe_on_commit(vault_home):
    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    text = "Centurion home is profile-scoped via get_centurion_home()."
    p1 = vault.propose(memory_type="core", text=text, rationale="a")
    vault.commit(p1.id)
    with pytest.raises(ValueError, match="Duplicate"):
        vault.propose(memory_type="core", text=text, rationale="b")


def test_vault_tool_json(vault_home):
    from agent.vault import initialize
    from tools.vault_tool import vault_tool

    initialize("test-passphrase-ok")
    status = json.loads(vault_tool(action="status"))
    assert status["success"] is True
    assert status["status"]["unlocked"] is True

    proposed = json.loads(
        vault_tool(
            action="propose",
            memory_type="experiential",
            text="Chose LAN-first Sovereign pairing over portal tokens.",
            rationale="Product decision",
        )
    )
    assert proposed["success"] is True
    pid = proposed["proposal"]["id"]

    committed = json.loads(vault_tool(action="commit", proposal_id=pid))
    assert committed["success"] is True

    searched = json.loads(vault_tool(action="search", query="LAN-first pairing"))
    assert searched["success"] is True
    assert searched["count"] >= 1


def test_profile_path_not_literal_home(vault_home):
    from agent.vault import initialize, get_vault_dir

    initialize("test-passphrase-ok")
    assert str(get_vault_dir()).startswith(str(vault_home))
    assert get_vault_dir() == vault_home / "vault"
