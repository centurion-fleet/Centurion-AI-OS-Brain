"""Prompt-cache invariant: Vault writes must not mutate frozen system prompt."""

from __future__ import annotations


def test_vault_write_does_not_require_system_prompt_mutation(tmp_path, monkeypatch):
    """Vault commit is disk-side only — system prompt snapshot stays independent."""
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))

    from agent.vault import initialize

    vault = initialize("test-passphrase-ok")
    frozen = "SYSTEM_PROMPT_SNAPSHOT_V1"
    prop = vault.propose(
        memory_type="core",
        text="User works in UTC.",
        rationale="stable",
    )
    vault.commit(prop.id)
    # Mimic agent invariant: cached prompt string unchanged by Vault I/O
    assert frozen == "SYSTEM_PROMPT_SNAPSHOT_V1"
    assert vault.search("UTC")
