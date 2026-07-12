---
title: Provider recovery
sidebar_position: 42
---

# Provider recovery

When your Centurion's thinking service breaks, you should not need a terminal to recover from your iPhone.

## What you will see

- **iPhone Connect**: Separate **Device link** and **Thinking service** cards. If thinking fails while the link is fine, you see **Fix Thinking Service** — not a generic offline state.
- **iPhone Chat**: A calm banner: *"Your Centurion is having trouble thinking right now. Tap to fix."*
- **iPhone You → Get Help**: Support codes and automatic recovery (see [Get Help](get-help.md)).
- **GTK desktop**: **Thinking Service** and **Support Tools** in Settings.

The iPhone **recovers** (restore last working setup). It does **not configure** providers — that happens on your Centurion computer.

## Recovery actions

| Action | Where | What it does |
|--------|-------|----------------|
| Fix Thinking Service | iPhone Connect / Chat banner | Restore last working setup; link to Get Help |
| Try to Fix Automatically | iPhone Get Help | Safe LKG restore + re-probe on the host |
| Send to Support | iPhone Get Help | Creates a short support code (e.g. `ABC-123`) |
| Restore last working setup | iPhone Fix sheet, GTK Settings | Applies the saved Last Known Good (LKG) snapshot |
| Change Thinking Service | GTK Settings only | Validated provider/model switch |
| `centurion provider status` | Host terminal / GTK | JSON health probe |
| `centurion support bundle --json` | Host / GTK | Generate support code locally |

## Last Known Good (LKG)

After a successful probe or chat turn, Centurion saves:

`~/.centurion/state/last_good_model.json`

The remote bridge may auto-restore LKG once when auth/model errors occur, then retry your message.

## Structured error codes

| Code | Meaning |
|------|---------|
| `LLM_AUTH_MISSING` | API key not configured on the host |
| `LLM_AUTH_INVALID` | Key rejected (401/403) |
| `LLM_MODEL_INVALID` | Model not found or non-agentic |
| `LLM_RATE_LIMIT` | Provider throttled (429) |
| `LLM_UNAVAILABLE` | Timeout or server error |
| `LLM_CONFIG_INVALID` | Config/provider resolution issue |

API keys are always entered on the host (GTK or `centurion setup`) — they never travel over the iPhone link.

## Host control plane commands

```bash
centurion provider status --json
centurion provider options --json
centurion provider set openrouter anthropic/claude-sonnet-4 --json
centurion provider restore --json
centurion support health --json
centurion support bundle --json
centurion support show ABC-123 --json
```

## Test matrix

1. Linked iPhone + healthy thinking → Connect shows two green states; no Fix button.
2. Break thinking on host → iPhone shows Needs attention; device link stays green.
3. Get Help → Send to Support → support code appears; bundle exists under `state/support_bundles/`.
4. Get Help → Try to Fix Automatically with LKG present → thinking returns to Working normally.
5. GTK Support Tools → Look Up Support Code → formatted summary (no secrets).
