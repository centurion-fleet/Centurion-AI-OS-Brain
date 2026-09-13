# Vault unlock — why it fails, and the plugin that fixes it

## The problem

Vault's decryption key lives in a module-level global
(`agent/vault/__init__.py` → `_shared_store`). Unlock is therefore
**process-local**.

- `centurion vault unlock` unlocks its own process, prints success, and exits. The
  key dies with it. It cannot unlock a long-running gateway/agent process.
- No daemon, no socket, no env-var passphrase, no `unlock` action on the `vault` tool.
- Stock install → `key_present: true`, `unlocked: false`, permanently. Reads and
  writes silently no-op.

## The fix — shipped

`agent.vault.auto_unlock()` reads the passphrase from `$CENTURION_VAULT_PASSPHRASE`
or the 0600 keyfile `$CENTURION_HOME/.vault-passphrase`, and unlocks **in-process**.
It is called from `agent/agent_init.py` when `vault.enabled` is true and
`vault.auto_unlock` is true (the default). Idempotent — only the first agent in a
process does the work — and it never raises, so a memory-layer problem cannot break a
session.

```bash
centurion vault init                                   # once, interactive
printf '%s\n' 'YOUR-PASSPHRASE' > ~/.centurion/.vault-passphrase
chmod 600 ~/.centurion/.vault-passphrase
centurion config set vault.enabled true
```

Note the keyfile is *outside* `vault/` on purpose: a copy or backup of `vault/`
alone then carries only ciphertext, not the passphrase. An invariant test
(`test_passphrase_file_lives_outside_vault_dir`) guards it.

## The fallback — a plugin, for Brains older than the fix

Plugins load **into the live gateway process** and can register lifecycle hooks. A
plugin that calls `open_vault(passphrase)` unlocks the shared store for the whole
process lifetime. No root needed — unlike patching the installed package, which is
usually root-owned and read-only.

## The plugin

`~/.centurion/plugins/vault-autounlock/plugin.yaml`:

```yaml
name: vault-autounlock
version: 1.0.0
description: "Unlock the offline Vault inside the live gateway/agent process at startup."
hooks:
  - on_session_start
  - pre_gateway_dispatch
```

`~/.centurion/plugins/vault-autounlock/__init__.py`:

```python
"""Unlock the offline Vault inside the live process.

Vault unlock state is process-local, so `centurion vault unlock` — a separate
short-lived process — can never unlock a running gateway. Plugins load into the
live process, so unlocking here works.
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

PASS_FILE = Path.home() / ".centurion" / ".vault-passphrase"

_lock = threading.Lock()
_done = False


def _unlock(**kwargs: Any) -> None:
    """Unlock the Vault in this process. Idempotent, never raises."""
    global _done
    with _lock:
        if _done:
            return
        try:
            from agent.vault import is_initialized, open_vault

            if not is_initialized() or not PASS_FILE.exists():
                logger.warning("vault-autounlock: not initialised; Vault stays locked")
                _done = True
                return
            passphrase = PASS_FILE.read_text().strip()
            if passphrase:
                vault = open_vault(passphrase)
                logger.info(
                    "vault-autounlock: vault unlocked (%s entries)",
                    vault.status().get("total_entries"),
                )
        except Exception:
            logger.exception("vault-autounlock: unlock failed")  # never break a session
        _done = True


def register(ctx) -> None:
    ctx.register_hook("on_session_start", _unlock)
    ctx.register_hook("pre_gateway_dispatch", _unlock)
    _unlock()          # deterministic at boot; Scrypt derivation is ~40 ms
```

## Install steps

1. Init the Vault once: `centurion vault init` (interactive), or call
   `agent.vault.initialize(pw)` from the venv python.
2. Store the passphrase **0600, outside `vault/`** — so a backup of `vault/` alone
   stays encrypted:
   ```bash
   printf '%s\n' 'YOUR-PASSPHRASE' > ~/.centurion/.vault-passphrase
   chmod 600 ~/.centurion/.vault-passphrase
   ```
3. Write the two plugin files above.
4. `centurion plugins enable vault-autounlock`
   — appends to `plugins.enabled` in `config.yaml`. **Plugins are opt-in**;
   nothing loads unless it is named there.
5. Restart so the plugin loads into the gateway: `centurion gateway restart`.
   It is usually a **user** service
   (`~/.config/systemd/user/centurion-gateway.service`), so no root is needed.
6. Verify — see below.

## Verification

`centurion vault status` runs in a **new** process, so it will still read
`Unlocked: False`. It cannot verify an unlock that lives in the gateway. Instead:

- Check the gateway log for `vault-autounlock: vault unlocked (N entries)`.
- Ask the agent to report `vault(action='status')` **from inside a gateway
  session** — that must read `unlocked: true`.
- Prove it end to end: propose → commit → search returns the entry.

```python
# Test through the real plugin manager (which is how the loader works).
from centurion_cli.plugins import discover_plugins, get_plugin_manager, invoke_hook
from agent.vault import open_vault

discover_plugins(force=True)
assert "vault-autounlock" in get_plugin_manager()._plugins
invoke_hook("on_session_start", session_id="verify")
assert open_vault().is_unlocked is True
```

## Pitfalls

- **Don't `import vault_autounlock` directly.** The directory name contains a
  hyphen; the loader slugs it to `centurion_plugins.vault_autounlock` and imports
  via `spec_from_file_location`. Test through the manager, as above.
- `vault.propose()` is **keyword-only**:
  `propose(memory_type=..., text=..., rationale=...)`.
- **`centurion vault install-model` used to be broken** — the "remaining commands
  need unlock" branch ran before the `install-model` dispatch, so it prompted for a
  passphrase it did not need and died with `EOFError` when run non-interactively.
  **Fixed:** the dispatch now runs before the unlock block, with a regression test
  (`test_install_model_does_not_prompt_for_passphrase`). If you fetch the GGUF by
  hand on an older build, the URL and destination are:
  ```
  https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf
  → ~/.centurion/vault/models/
  ```
- **Downloading the GGUF is not enough.** `get_embedder()` also needs
  `llama-cpp-python` importable in the *running* venv; otherwise the embedder
  silently stays `stub-hash-v1` (keyword-ish, not semantic) even though the model
  file is present. The `embed_base_url` config key is declared but consumed
  nowhere — there is no loopback-server route.
- **No entry-delete API** exists in `agent/vault/store.py`. To clear test data,
  remove `vault.db*` + `vault.key.wrapped` and re-init; the passphrase file is
  reused.
- **Never restart the gateway while a reply is still pending** — the restart kills
  the process running the current turn.

## Security — tell the owner

The passphrase sits on disk readable by anything running as the agent's user,
including the agent. Vault's at-rest encryption therefore protects against disk
theft, leaked backups, and other local users — **not** against the agent, malware,
or root while unlocked. This matches the threat model in `agent/vault/crypto.py`.

Offer the owner the choice explicitly: hold the passphrase themselves (unlocking
manually, which costs the agent autonomous write access) versus delegating it for
autonomous use. Do not decide it silently on their behalf.

## The real fix belongs upstream

Any of these removes the need for the workaround:

1. Auto-unlock at gateway/agent startup from a keyfile or a
   `CENTURION_VAULT_PASSPHRASE` env var.
2. An `unlock` action on the `vault` tool, so an agent can unlock itself in-process.
3. **Honest reporting** — distinguish "locked" from "unusable", and tell the agent
   the write path is inactive instead of failing silently. A memory layer that
   no-ops without a warning is worse than one that is loudly off.
