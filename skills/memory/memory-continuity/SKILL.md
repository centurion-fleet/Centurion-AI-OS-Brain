---
name: memory-continuity
description: Use when the user references a past conversation, asks "where did we leave X", resumes an unfinished thread, or a new session starts and you need yesterday's trail. Reconstruct cross-session context via session_search and write good session-end digests.
version: 1.0.0
author: Centurion Fleet
license: MIT
metadata:
  centurion:
    tags: [memory, continuity, session-recall, digests]
    related_skills: [memory-hygiene, memory-architecture]
---

# Memory Continuity

## Overview

A Centurion should *know* yesterday rather than re-read it each morning. Session
Recall holds the full transcripts; the continuity digest summarises them. This
skill covers both directions: pulling the thread back up (read path) and leaving
a good thread for the next session (write path).

## When to Use

- User references something from a past conversation.
- Resuming work after a gap ("where were we on X?").
- A new session starts and you need recent context beyond the injected digest.

## Reconstruct context (read path)

1. `session_search(query)` for discovery — FTS5, returns bookends + a ±5 window.
2. To go deeper, scroll: `session_search(session_id, around_message_id, window)`.
3. Browse with `session_search()` (no args) when the user doesn't name a topic.
4. Use Vault `search` for long-horizon "who we became" context.

## Write a good session-end digest (write path)

The session-end digest (`agent/memory_continuity.py`) summarises into a 3–6
sentence experiential note: what mattered, unfinished threads, decisions.

- First person, as the agent.
- No secrets, no API keys, no full transcripts.
- Capture "where we left off" — that is what the next session needs most.

## Common Pitfalls

1. Asking the user to repeat themselves when session_search can find it.
2. Dumping whole transcripts into Vault or Hot Cache.
3. Fabricating past context when the search returns empty — say so plainly instead.

## Verification Checklist

- [ ] Every reconstructed claim traces to an actual past message.
- [ ] Anything unverifiable is marked "I believe" / "I don't know", not asserted.
- [ ] The digest captures "where we left off" and omits secrets/transcripts.
