"""Tests for Vault auto-unlock at agent startup.

Vault unlock state is process-local (the DEK lives in a module-level global), so
the `centurion vault unlock` CLI — a separate, short-lived process — can never
unlock a running gateway. `auto_unlock()` closes that gap in-process.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import pytest


@pytest.fixture
def vault_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    monkeypatch.delenv("CENTURION_VAULT_PASSPHRASE", raising=False)
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


def _fresh_process(monkeypatch):
    """Simulate a new process: drop the in-memory shared store."""
    import agent.vault as vault_mod

    vault_mod._shared_store = None
    vault_mod._shared_embedder = None


def test_auto_unlock_from_env_var(vault_home, monkeypatch):
    from agent.vault import auto_unlock, initialize, open_vault

    initialize("test-passphrase-ok")
    _fresh_process(monkeypatch)
    monkeypatch.setenv("CENTURION_VAULT_PASSPHRASE", "test-passphrase-ok")

    assert open_vault().is_unlocked is False  # nothing unlocked it yet
    assert auto_unlock() is True
    assert open_vault().is_unlocked is True


def test_auto_unlock_from_keyfile(vault_home, monkeypatch):
    from agent.vault import auto_unlock, initialize, open_vault
    from agent.vault.paths import passphrase_file_path

    initialize("test-passphrase-ok")
    _fresh_process(monkeypatch)

    keyfile = passphrase_file_path()
    keyfile.write_text("test-passphrase-ok\n", encoding="utf-8")
    os.chmod(keyfile, 0o600)

    assert auto_unlock() is True
    assert open_vault().is_unlocked is True


def test_env_var_takes_precedence_over_keyfile(vault_home, monkeypatch):
    from agent.vault import auto_unlock, initialize, open_vault
    from agent.vault.paths import passphrase_file_path

    initialize("correct-passphrase")
    _fresh_process(monkeypatch)

    # Stale/incorrect keyfile must not win over an explicit env var.
    passphrase_file_path().write_text("wrong-passphrase\n", encoding="utf-8")
    monkeypatch.setenv("CENTURION_VAULT_PASSPHRASE", "correct-passphrase")

    assert auto_unlock() is True
    assert open_vault().is_unlocked is True


def test_auto_unlock_without_passphrase_returns_false(vault_home, monkeypatch):
    from agent.vault import auto_unlock, initialize, open_vault

    initialize("test-passphrase-ok")
    _fresh_process(monkeypatch)

    assert auto_unlock() is False
    assert open_vault().is_unlocked is False


def test_wrong_passphrase_returns_false_and_does_not_raise(vault_home, monkeypatch):
    from agent.vault import auto_unlock, initialize, open_vault

    initialize("test-passphrase-ok")
    _fresh_process(monkeypatch)
    monkeypatch.setenv("CENTURION_VAULT_PASSPHRASE", "definitely-wrong")

    assert auto_unlock() is False  # must never raise
    assert open_vault().is_unlocked is False


def test_auto_unlock_when_not_initialized_returns_false(vault_home, monkeypatch):
    from agent.vault import auto_unlock

    monkeypatch.setenv("CENTURION_VAULT_PASSPHRASE", "anything")
    assert auto_unlock() is False


def test_auto_unlock_is_idempotent(vault_home, monkeypatch):
    from agent.vault import auto_unlock, initialize, open_vault

    initialize("test-passphrase-ok")
    _fresh_process(monkeypatch)
    monkeypatch.setenv("CENTURION_VAULT_PASSPHRASE", "test-passphrase-ok")

    assert auto_unlock() is True
    assert auto_unlock() is True
    assert open_vault().is_unlocked is True


def test_passphrase_file_lives_outside_vault_dir(vault_home):
    """Security invariant: backing up vault/ alone must not carry the passphrase."""
    from agent.vault.paths import get_vault_dir, passphrase_file_path

    vault_dir = get_vault_dir().resolve()
    keyfile = passphrase_file_path().resolve()

    assert vault_dir not in keyfile.parents


def test_read_passphrase_returns_none_when_nothing_available(vault_home, monkeypatch):
    from agent.vault import read_passphrase

    assert read_passphrase() is None

    # An empty keyfile is treated as "no passphrase", not as an empty string.
    from agent.vault.paths import passphrase_file_path

    passphrase_file_path().write_text("   \n", encoding="utf-8")
    assert read_passphrase() is None


# --- regression: `centurion vault install-model` must not demand a passphrase ---


def test_install_model_does_not_prompt_for_passphrase(monkeypatch):
    """install-model only downloads a GGUF — it must not hit the unlock path.

    Previously the "remaining commands need unlock" block ran first, so this
    prompted for a passphrase it did not need and died with EOFError when run
    non-interactively.
    """
    from centurion_cli import vault as cli_vault

    called = {}
    monkeypatch.setattr(
        cli_vault, "_install_embedding_model", lambda **kw: called.update(kw)
    )

    def _explode(confirm: bool = False):
        raise AssertionError("install-model prompted for a passphrase")

    monkeypatch.setattr(cli_vault, "_prompt_passphrase", _explode)

    args = argparse.Namespace(vault_command="install-model", url="", force=False)
    cli_vault.vault_command(args)

    assert called == {"url": "", "force": False}
