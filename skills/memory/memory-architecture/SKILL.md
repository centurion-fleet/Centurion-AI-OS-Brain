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
