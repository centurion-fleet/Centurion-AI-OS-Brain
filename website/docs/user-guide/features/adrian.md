---
sidebar_position: 42
title: Adrian — Support Guide
---

# Adrian — Centurion's support guide

**Adrian** is Centurion's cloud support guide for CenturionAI Remote (iPhone). Centurion operates Adrian so customers never need their own API keys.

## Why Adrian exists

Centurion uses AI to support its own customers — the same philosophy that powers the product: AI should help people stay on mission, not leave them debugging infrastructure alone.

Adrian is **separate** from your Centurion on your computer:

| | Your Centurion (LAN) | Adrian (cloud) |
|---|---|---|
| Connection | Private network link | Internet |
| Purpose | Your AI companion | App and connection support |
| When it works | Same Wi‑Fi as your computer | Whenever your phone is online |
| Who pays | Your thinking provider (on computer) | Centurion |

## Using Adrian on iPhone

1. Tap the **Adrian** button at the bottom of any main tab.
2. Accept the one-time privacy notice (what Adrian can and cannot see).
3. Describe what's in the way — plain language is fine.
4. Follow Adrian's steps, or tap suggested actions (Open Connect, Try to Fix Automatically, etc.).

Adrian does **not** read your Centurion chat history. It receives only sanitized context: link state, thinking health in plain words, whether you have a mission set, and an optional support code you already generated.

## Get Help vs Adrian

- **Adrian** — always available when online; walks you through fixes in conversation.
- **Get Help** — requires a device link; creates support codes and runs auto-fix on your computer.

Use both: Adrian for immediate guidance; Get Help when you need a code for Centurion support.

## Operating Adrian (Centurion team)

Run the Adrian API on Centurion infrastructure:

```bash
export CENTURION_HERALD_OPENAI_API_KEY=sk-...
export CENTURION_HERALD_SERVER_KEY=optional-client-auth-key
centurion adrian serve --host 0.0.0.0 --port 9120
```

Production endpoint: `https://adrian.centurion.ai` (configured in the iOS app's `CenturionAdrianBaseURL`).

Knowledge base and system prompt live in `centurion_cli/adrian/knowledge.md` and `prompts.py` — update these as new support patterns emerge.

Environment variables:

| Variable | Purpose |
|---|---|
| `CENTURION_HERALD_OPENAI_API_KEY` | Model API key (Centurion-operated) |
| `CENTURION_HERALD_MODEL` | Default `gpt-4o-mini` |
| `CENTURION_HERALD_SERVER_KEY` | Optional shared secret for client requests |
| `CENTURION_HERALD_CORS_ORIGINS` | CORS allowlist (default `*`) |

## Privacy

- Adrian conversations are stored only on the device during the session (not in Centurion chat sessions).
- Server-side: rate-limited by anonymous install ID; no Centurion home directory access.
- Secrets are redacted from context server-side before any model call.
