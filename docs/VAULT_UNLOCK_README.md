# README — Vault cannot be unlocked from the CLI (and how to fix it)

**Audience:** every Centurion Brain, and whoever cuts the release.
**Status:** fixed. Two gaps, closed in sequence:
`auto_unlock()` (7.0.0+) closed the *process-local* gap; **`bootstrap()` (7.0.6)** closes
the *first-run* gap — it creates the Vault and provisions its passphrase on first startup,
so a delivered Brain has working memory with no terminal and no passphrase to type.
**Action required:** none — memory turns itself on. If `centurion vault status` still
reports `Key present: False` on a current build, that is a fault to report, not a chore
to perform.

---

## TL;DR

`centurion vault unlock` **does not work** for a running gateway. It unlocks its own
short-lived process, prints a success message, and exits — taking the decryption key
with it. There is no daemon, no socket, no env-var passphrase, and the `vault` tool
has no `unlock` action.

**Symptom:** `centurion vault status` reports `Key present: True` and
`Unlocked: False`, permanently. Every Vault read returns nothing and every Vault
write is silently skipped. Setting `vault.enabled: true` changes nothing on its own.

**Cause:** the decryption key is held in a module-level global
(`agent/vault/__init__.py` → `_shared_store`), so unlock state is **process-local**.
A CLI invocation is a different process from the gateway. It can never unlock it.

---

## Why this matters

The Vault is the long-horizon memory layer. When it is silently locked:

- `prefetch_for_query()` returns `""` — no long-term recall is injected.
- `_propose_vault_experiential()` silently skips — session digests fall back to
  `memories/CONTINUITY.md` (rolling, capped at 8 entries).
- Nothing errors. Nothing warns. It just quietly does not work.

A Centurion can run for months believing it has a sealed long-term memory that has
never once been written to.

---

## Diagnosis (60 seconds)

```bash
centurion vault status
```

If you see `Key present: True` **and** `Unlocked: False` after running
`centurion vault unlock`, you have this issue.

Confirm the process-locality directly:

```bash
# Unlock, then immediately check from a *separate* process.
centurion vault unlock
centurion vault status        # still Unlocked: False
```

---

## Fix A — shipped: `auto_unlock()` at agent startup

The Vault now unlocks **in-process** when an agent starts, from either:

1. the `CENTURION_VAULT_PASSPHRASE` environment variable, or
2. a 0600 keyfile at `$CENTURION_HOME/.vault-passphrase`.

Implementation: `agent.vault.auto_unlock()`, called from `agent/agent_init.py` when
`vault.enabled` is true and `vault.auto_unlock` is true (both now the default path for
enabled Vaults). It is idempotent — only the first agent in a process does the work —
and it never raises, so a memory-layer problem cannot break a session.

```bash
centurion vault init                                  # once, interactive
printf '%s\n' 'YOUR-PASSPHRASE' > ~/.centurion/.vault-passphrase
chmod 600 ~/.centurion/.vault-passphrase
centurion config set vault.enabled true
# that's it — auto_unlock handles the rest at agent startup
```

**Keyfile placement matters.** The keyfile lives in `$CENTURION_HOME` but
*outside* `vault/`, so copying or backing up the `vault/` directory alone does not
carry the passphrase with it — the ciphertext stays encrypted in transit. Do not
"tidy" it into `vault/`. A test asserts this invariant
(`test_passphrase_file_lives_outside_vault_dir`).

**Verify it took effect:**
- The `vault` tool must report `unlocked: true` **from inside a gateway session**.
  (`centurion vault status` runs in its own process and will still say `false` — it
  cannot observe an unlock that lives in the gateway.)
- Watch the log for `Vault: auto-unlocked (N entries)`.

## Fix B — fallback for pre-fix builds: the local plugin

On a Brain still running **v5.3.10 or earlier**, `auto_unlock()` does not exist. Use a
plugin instead: plugins load **into the live gateway process**, so a plugin that calls
`open_vault(passphrase)` makes the unlock persist for that process's lifetime.

Create `~/.centurion/plugins/vault-autounlock/plugin.yaml`:

```yaml
name: vault-autounlock
version: 1.0.0
description: "Unlock the offline Vault inside the live gateway/agent process at startup."
hooks:
  - on_session_start
  - pre_gateway_dispatch
```

Create `~/.centurion/plugins/vault-autounlock/__init__.py`:

```python
"""Unlock the offline Vault inside the live process.

Vault unlock state is process-local (the key lives in a module-level global),
so `centurion vault unlock` — a separate short-lived process — can never unlock
a running gateway. Plugins load into the live process, so unlocking here works.
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
    _unlock()          # deterministic at boot: ~40 ms Scrypt derivation
```

Then:

```bash
centurion plugins enable vault-autounlock   # plugins are opt-in
centurion gateway restart
```

**Remove this plugin once the Brain is upgraded past the fix** — it is redundant and
does the same work twice (harmlessly, but it should not be left behind).

---

## Related bugs found in the same area (v5.3.10)

- **`centurion vault install-model` was unusable — FIXED in this release.** The
  "remaining commands need unlock" branch ran *before* the `install-model` dispatch,
  so it prompted for a passphrase it did not need, then died with `EOFError` when run
  non-interactively. The download needs no vault access at all. The dispatch now runs
  first, with a regression test.
- **`embed_base_url` is dead config.** Declared in `centurion_cli/config.py` with
  the comment "loopback only if set", but consumed nowhere in the codebase. There
  is no loopback embedding-server route. Do not plan around it.
- **The GGUF alone is not enough.** `get_embedder()` also needs
  `llama-cpp-python` importable in the *running* venv. Without it the model file
  sits inert and the embedder stays `stub-hash-v1` (crude keyword-ish recall,
  not semantic). Installing into a root-owned venv needs root.
- **No entry-delete API** exists in `agent/vault/store.py`. To clear test data,
  remove `vault.db*` + `vault.key.wrapped` and re-init (the passphrase file is
  reused).

---

## Security note — state this honestly to the owner

Storing the passphrase on disk means anything running as the agent's user can read
it — including the agent. Vault's at-rest encryption therefore protects against
**disk theft, leaked backups, and other local users**, but **not** against the
agent itself, malware, or root while unlocked. This matches the threat model
already documented in `agent/vault/crypto.py`.

**Therefore: do not treat the Vault as a place for secrets that would harm the
owner if the agent were compromised.** The owner should be told this explicitly
before the Vault is enabled on their Brain, and should get the choice of holding
the passphrase themselves (unlocking manually, losing agent write access) versus
delegating it for autonomous use.

---

## Verification checklist for the release manager

- [ ] `vault(action='status')` from inside a gateway session reads `unlocked: true`
      (on an upgraded Brain with `vault.enabled` and a keyfile present).
- [ ] The log shows `Vault: auto-unlocked (N entries)` at agent startup.
- [ ] A write round-trip succeeds (propose → commit → search returns the entry).
- [ ] `tests/agent/vault/` passes, including the auto-unlock and `install-model`
      regression tests.
- [ ] The owner has been told the passphrase-on-disk tradeoff in plain language.
- [ ] `.release_notes.md` (auto-generated by `scripts/release.py` from commit
      subjects) lists this under **✨ Features** — a hand edit there will be
      overwritten, so the commit subject is what matters.
