"""Tests for unattended Vault bootstrap.

`auto_unlock()` closed the process-local gap, but it still needed a Vault that
existed and a passphrase it could read — and a delivered Brain had neither. No
installer ran `vault init`, nothing provisioned a passphrase, and the shipped
config default was `enabled: false`. So every customer machine reported
`key_present: False`, `Entries: 0`, and a memory layer that silently did nothing.

`bootstrap()` makes a Centurion arrive able to remember without a human in a
terminal. These tests pin the two properties that make it safe to run
unattended: it creates a Vault when there is none, and it NEVER touches one that
already exists.
"""

from __future__ import annotations

import os
import stat
import threading

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


def _fresh_process():
    """Simulate a new process: drop the module-level shared store."""
    import agent.vault as vault_mod

    vault_mod._shared_store = None
    vault_mod._shared_embedder = None


def test_first_run_creates_and_unlocks_the_vault(vault_home):
    from agent.vault import bootstrap, is_initialized, open_vault
    from agent.vault.paths import passphrase_file_path

    assert is_initialized() is False
    assert bootstrap() is True
    assert is_initialized() is True
    assert open_vault().is_unlocked is True

    keyfile = passphrase_file_path()
    assert keyfile.exists(), "the passphrase must be provisioned for auto_unlock"
    assert keyfile.read_text(encoding="utf-8").strip(), "passphrase must not be empty"


def test_provisioned_passphrase_is_mode_0600(vault_home):
    from agent.vault import bootstrap
    from agent.vault.paths import passphrase_file_path

    bootstrap()
    mode = stat.S_IMODE(os.stat(passphrase_file_path()).st_mode)
    assert mode == 0o600, f"passphrase file is {oct(mode)}, must be 0600"


def test_passphrase_lives_outside_the_vault_directory(vault_home):
    """Copying the vault dir must not carry the passphrase with it."""
    from agent.vault import bootstrap
    from agent.vault.paths import get_vault_dir, passphrase_file_path

    bootstrap()
    keyfile = passphrase_file_path()
    vault_dir = get_vault_dir()
    assert keyfile.parent != vault_dir
    assert vault_dir not in keyfile.parents


def test_two_machines_get_different_passphrases(vault_home, tmp_path, monkeypatch):
    """Generated, not a constant — otherwise one leaked key opens every Brain."""
    from agent.vault import bootstrap
    from agent.vault.paths import passphrase_file_path

    bootstrap()
    first = passphrase_file_path().read_text(encoding="utf-8").strip()

    other = tmp_path / "other" / ".centurion"
    other.mkdir(parents=True)
    monkeypatch.setenv("CENTURION_HOME", str(other))
    _fresh_process()

    bootstrap()
    second = passphrase_file_path().read_text(encoding="utf-8").strip()
    assert first != second


def test_bootstrap_is_idempotent(vault_home):
    from agent.vault import bootstrap
    from agent.vault.paths import wrapped_key_path

    bootstrap()
    key_before = wrapped_key_path().read_bytes()
    _fresh_process()

    assert bootstrap() is True
    assert wrapped_key_path().read_bytes() == key_before, (
        "a second bootstrap must not re-key an existing Vault"
    )


def test_never_clobbers_an_existing_vault_with_no_passphrase(vault_home):
    """The safety property. A lost passphrase is unrecoverable, and the wrapped
    key is the only route back in — so bootstrap must refuse, not reset."""
    from agent.vault import bootstrap, initialize, is_initialized, open_vault
    from agent.vault.paths import passphrase_file_path, wrapped_key_path

    initialize("the-owners-own-passphrase")
    _fresh_process()
    key_before = wrapped_key_path().read_bytes()

    # The owner's passphrase is nowhere bootstrap can read it.
    passphrase_file_path().unlink(missing_ok=True)

    assert bootstrap() is False, "must not claim success when it cannot unlock"
    assert wrapped_key_path().read_bytes() == key_before, "the key was overwritten"
    assert is_initialized() is True
    assert open_vault().is_unlocked is False


def test_existing_vault_unlocks_from_the_keyfile(vault_home):
    from agent.vault import bootstrap, initialize
    from agent.vault import write_passphrase_file

    initialize("known-passphrase-123")
    _fresh_process()
    write_passphrase_file("known-passphrase-123")

    assert bootstrap() is True


def test_operator_supplied_passphrase_is_used_and_not_copied_to_disk(
    vault_home, monkeypatch
):
    """An operator who sets the env var has made a deliberate choice; we use it
    and do not duplicate their secret onto disk behind their back."""
    from agent.vault import bootstrap
    from agent.vault.paths import passphrase_file_path

    monkeypatch.setenv("CENTURION_VAULT_PASSPHRASE", "operator-chosen-passphrase")
    assert bootstrap() is True
    assert not passphrase_file_path().exists()


def test_create_false_does_not_create(vault_home):
    from agent.vault import bootstrap, is_initialized

    assert bootstrap(create=False) is False
    assert is_initialized() is False


def test_bootstrap_never_raises_on_a_hostile_home(vault_home, monkeypatch):
    """Called from agent startup: a failure here must not take the Brain down."""
    import agent.vault as vault_mod

    def boom(*_a, **_kw):
        raise RuntimeError("disk on fire")

    monkeypatch.setattr(vault_mod, "open_vault", boom)
    assert vault_mod.bootstrap() is False


def test_bootstrap_survives_concurrent_first_runs(vault_home):
    """Two agents in one process (or a racing first launch) must not both
    initialise and leave a half-written key."""
    from agent.vault import bootstrap, is_initialized

    results: list[bool] = []
    lock = threading.Lock()

    def run():
        _fresh_process()
        outcome = bootstrap()
        with lock:
            results.append(outcome)

    threads = [threading.Thread(target=run) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert is_initialized() is True
    assert any(results), "at least one caller must end up with a usable Vault"
