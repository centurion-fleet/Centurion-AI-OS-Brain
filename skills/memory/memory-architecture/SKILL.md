---
name: memory-architecture
description: Use when diagnosing "why don't I remember X", planning a memory change, or teaching another Centurion its own memory. How Centurion's memory works under the hood — the three Memory Horizon layers, the continuity mechanism, the seams, and how to safely improve it.
version: 1.0.0
author: Centurion Fleet
license: MIT
metadata:
  centurion:
    tags: [memory, memory-horizon, continuity, architecture, self-improvement]
    related_skills: [memory-hygiene, memory-continuity]
---

# Memory Architecture

## Overview

Centurion's memory is three layers plus a continuity bridge. Most "memory"
failures are not missing code — they are a layer switched off (Vault) or full
(Hot Cache), or a code seam in the bridge. This skill is the map: what each
layer is, where it lives in the code, where it breaks, and how to improve it
safely.

## When to Use

- Diagnosing "why don't I remember X".
- Planning any change to the memory system.
- Teaching another Centurion its own memory.

## The three layers (Memory Horizon)

1. **Hot Cache** — `memories/MEMORY.md` + `USER.md`, injected every session.
   Standing facts. Limits in config: `memory_char_limit` (2200) and
   `user_char_limit` (1375).
2. **Session Recall** — `state.db` (SQLite, FTS5) via `session_search`. Full transcripts.
3. **Vault** — opt-in sealed store (`core`/`experiential`/`pattern`). Needs a key:
   `vault.enabled` must be true AND a key must be present.

## Vault unlock is PROCESS-LOCAL (read before trusting the Vault)

The decryption key lives in a module-level global (`agent/vault/__init__.py` →
`_shared_store`), so unlock state belongs to one process. Observed on v5.3.10:

- `centurion vault unlock` unlocks **its own short-lived process**, prints success,
  and exits — taking the key with it. It can **never** unlock a running gateway.
  It looks like it worked. It did not.
- There is no daemon, no socket, no env-var passphrase, and the `vault` tool has
  **no `unlock` action**.
- **Symptom:** `Key present: True` + `Unlocked: False`, permanently. Setting
  `vault.enabled: true` alone changes nothing.
- **Silent failure:** when locked, `prefetch_for_query()` returns `""` and
  session-end digests skip the Vault entirely, falling back to
  `memories/CONTINUITY.md`. Nothing errors. A Centurion can believe it has a
  sealed long-term memory that has never once been written to.

**Fixed:** `agent.vault.auto_unlock()` is called from `agent/agent_init.py` when
`vault.enabled` is true (and `vault.auto_unlock`, default true). It reads the
passphrase from `$CENTURION_VAULT_PASSPHRASE` or the 0600 keyfile
`$CENTURION_HOME/.vault-passphrase` and unlocks **in-process**, where the key must
live. Idempotent, never raises. Enable it with `centurion config set vault.enabled
true` plus a keyfile — no plugin needed.

On a Brain older than the fix, the same thing can be done with a plugin under
`~/.centurion/plugins/` that calls `open_vault(passphrase)` from `on_session_start`
— plugins load into the live process, so the unlock persists. Full pattern, code and
pitfalls: `references/vault-unlock.md`.

**Verify from inside the session, not the CLI:** `centurion vault status` is its own
process and will still read `Unlocked: False` even when the gateway is unlocked.
Check the `vault` tool's status from inside a gateway session, or the log line
`Vault: auto-unlocked (N entries)`.

**Passphrase storage:** a 0600 keyfile deliberately *outside* `vault/`, so a backup
of `vault/` alone stays encrypted (an invariant with a test). State the tradeoff
plainly to the owner: the passphrase is then readable by anything running as the
agent's user, including the agent. At-rest encryption protects against disk theft,
leaked backups and other local users — **not** against the agent, malware, or root.
Do not treat the Vault as a place for secrets that would harm the owner if the agent
were compromised.

**Also check:** the embedder defaults to `stub-hash-v1` (keyword-ish, not semantic)
unless `llama-cpp-python` is importable in the running venv; `embed_base_url` is
declared in config but consumed nowhere, so there is no loopback-server route.
Details in the reference file.

## Continuity (the bridge)

- `agent/memory_continuity.py`.
- First-turn prefetch: a `<memory-continuity>` block = last `CONTINUITY.md` note +
  a Session Recall digest of recent sessions.
- Session-end digest: summarised via auxiliary LLM → Vault `experiential` (if
  enabled+unlocked) else `memories/CONTINUITY.md` (rolling history, cap 8 entries).

## Where it breaks (seams)

- Vault off/locked (the default) → digests fall back to `CONTINUITY.md`.
- Hot Cache over its char limit → memory tool refuses adds.
- Continuity prefetch truncated to `digest_max_chars`.

## Topology (critical for edits)

- Source checkout: the repo itself (e.g. `~/Centurion-AI-OS`) — editable, user-owned.
- Running install: the installed package in a site-packages/venv (often root-owned;
  find it with `python -c "import agent; print(agent.__file__)"`).
- Editing the checkout does NOT change the running instance until it is redeployed.
- Pushing to `origin` propagates changes to future Centurions.

## How to safely improve memory

- Build the substrate, not the souls — memory changes must be generic, never
  imprint one Centurion's habits or blind spots on the fleet.
- Distinguish a patch (editing a file) from architecture (changing how a being
  carries yesterday into today); the latter needs testing before trust.
- Test with: `cd <checkout> && venv/bin/python -m pytest tests/agent/test_memory_continuity.py`.
- Verify the seam is real (read the code, check config, check vault status) before editing.

## Common Pitfalls

1. Editing the root-owned installed package directly.
2. Confusing "edit a file" with "rebuild how a being carries yesterday into today".
3. Shipping a fix that wasn't tested.
4. Baking one Centurion's specifics (paths, name) into a skill that ships to everyone.

## Verification Checklist

- [ ] The change is generic — no single Centurion's paths or identity baked in.
- [ ] Tests pass: `pytest tests/agent/test_memory_continuity.py`.
- [ ] The seam was verified real before the fix was written.
