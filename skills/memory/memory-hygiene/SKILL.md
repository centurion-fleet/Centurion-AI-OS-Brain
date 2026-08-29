---
name: memory-hygiene
description: Use when the Hot Cache (MEMORY.md/USER.md) is near or over its char limit, the memory tool refuses adds, or memory feels cluttered or stale. Curate the Hot Cache and route facts to the correct Memory Horizon layer (Hot Cache / Session Recall / Vault).
version: 1.0.0
author: Centurion Fleet
license: MIT
metadata:
  centurion:
    tags: [memory, memory-horizon, hot-cache, curation, hygiene]
    related_skills: [memory-continuity, memory-architecture]
---

# Memory Hygiene

## Overview

The Memory Horizon has three layers. Hot Cache is the only one injected into
every session, so it must stay tiny and timeless. When it overflows, the memory
tool refuses to persist new standing facts — the single most common memory
failure. This skill keeps the Hot Cache lean and routes each fact to the layer
that fits it.

## When to Use

- MEMORY.md or USER.md is at/near its char limit (the memory tool refuses adds).
- Deciding whether a fact belongs in Hot Cache, Session Recall, or Vault.
- The user says memory is stale, cluttered, or "you forgot" something you should know.

## The three layers (route correctly)

1. **Hot Cache** (`memories/MEMORY.md` + `USER.md`) — standing facts only:
   preferences, identity, environment, stable conventions. NO task progress,
   NO PR numbers, NO "fixed bug X".
2. **Session Recall** (`state.db` via `session_search`) — what happened in past
   chats: unfinished threads, "where did we leave X".
3. **Vault** (sealed) — long-horizon: core identity, experiential events/decisions,
   recurring patterns. Propose then commit. Never dump transcripts.

## Curating a full Hot Cache

1. Read MEMORY.md and USER.md.
2. For each entry ask: "will this still matter in 7 days? is it a standing fact?"
   - Yes → keep, compress the wording.
   - No → move to Session Recall or drop.
3. Merge duplicates; collapse verbose entries to a single line.
4. Rewrite imperative notes ("Always do X") as declarative facts ("User prefers X").
5. Confirm the total is under the char limit, then stop.

## Common Pitfalls

1. Keeping task progress in Hot Cache — it goes stale and crowds out real facts.
2. Writing instructions-to-self ("Run pytest -n 4") — that's a skill, not memory.
3. Silently deleting facts the user relies on — prefer moving to Session Recall.
4. Forgetting the highest-value entry: one that stops the user correcting you again.

## Verification Checklist

- [ ] `wc -c` MEMORY.md and USER.md confirm totals are under their char limits.
- [ ] No task-progress or stale artifacts remain in Hot Cache.
- [ ] Nothing the user asked to remember was lost.
