# Vault

Offline sealed long-term memory for Centurion AI OS.

:::info Memory Horizon — Vault
Vault is the **far field** of **[Memory Horizon](./memory-layers.md)**. Near field: **Hot Cache** ([MEMORY.md / USER.md](./memory.md)). Mid field: **Session Recall** ([sessions](../sessions.md)).
:::

Vault stores **Core Facts**, **Experiential Memory**, and **Pattern Memory** under `{CENTURION_HOME}/vault/` with AES-256-GCM encryption at rest. It is 100% local — no cloud sync, no telemetry, no external embedding APIs.

It **complements** the small curated hot cache (`MEMORY.md` / `USER.md`). Hot-cache facts stay in the `memory` tool; long-horizon archives go in Vault.

## Threat model (honest)

| Situation | Protected? |
|-----------|------------|
| Stolen disk / backup while Vault is locked | Yes |
| Other local users (file modes 0o700 / 0o600) | Mostly |
| Root / malware while Vault is unlocked | **No** — the key is in process memory |

Do not treat Vault as protection against a compromised host while Centurion is running.

## Quick start

```bash
centurion vault init          # create key + empty DB (passphrase ≥ 8 chars)
centurion vault unlock        # unlock for this process
centurion vault status
centurion vault search "preference"
centurion vault lock          # clear FTS plaintext index
```

## Agent tool

The `vault` tool supports: `status`, `propose`, `commit`, `reject`, `search`, `get`, `proposals`.

Always **propose then commit**. Never dump full transcripts — use `session_search` for that.

## Memory types

| Type | Use for |
|------|---------|
| `core` | Stable identity facts and durable preferences |
| `experiential` | Significant events and decisions with context |
| `pattern` | Recurring workflows (“when X, do Y”) |

## Search

While unlocked, Vault combines SQLite FTS5 keyword search with local semantic embeddings (stub hash embedder by default; optional local GGUF via `vault/models/`).

## Config

```yaml
vault:
  enabled: false
  prefetch_on_turn: false
  max_entry_chars: 4000
  hybrid_fts_weight: 0.4
  hybrid_semantic_weight: 0.6
```

## Related

- [Memory Horizon](./memory-layers.md) — full three-layer model
- [Persistent Memory](./memory.md) — Hot Cache (`MEMORY.md` / `USER.md`)
- Collaborations on Remote — mission cockpit; sealed outcomes return as “Ready for you” (separate from Vault memory)
