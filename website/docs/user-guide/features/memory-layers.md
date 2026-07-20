---
title: "Memory Horizon"
sidebar_label: "Memory Horizon"
sidebar_position: 2
description: "Centurion's three-layer memory model — Hot Cache, Session Recall, and Vault"
---

# Memory Horizon

**Memory Horizon** is how Centurion remembers — three layers that stretch from always-on essentials to sealed long-term archives. Not one opaque blob. Not cloud sync. Local, deliberate, and designed so each layer has one job.

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'primaryColor': '#1a1a30', 'primaryTextColor': '#e8e4dc', 'primaryBorderColor': '#FFD700', 'lineColor': '#9a968e', 'secondaryColor': '#0f0f18', 'tertiaryColor': '#14142a'}}}%%
flowchart TB
  subgraph MH["Memory Horizon"]
    direction TB
    H1["① Hot Cache<br/>MEMORY.md · USER.md<br/>~1,300 tokens · every session"]
    H2["② Session Recall<br/>state.db · session_search<br/>Full transcripts · on demand"]
    H3["③ Vault<br/>Encrypted Core · Experiential · Pattern<br/>Passphrase unlock · opt-in"]
  end

  You(["You"]) --> Agent(["Centurion"])
  Agent -->|"always in prompt"| H1
  Agent -->|"when past chats matter"| H2
  Agent -->|"when durable facts matter"| H3

  H1 -.->|"keep small"| H2
  H2 -.->|"don't dump transcripts here"| H3

  classDef hot fill:#2a2410,stroke:#FFD700,stroke-width:2px,color:#FFEB80
  classDef mid fill:#14142a,stroke:#C89222,stroke-width:1.5px,color:#e8e4dc
  classDef far fill:#0a1218,stroke:#6E8B9E,stroke-width:1.5px,color:#c8d4dc
  class H1 hot
  class H2 mid
  class H3 far
```

### How a turn reaches across the horizon

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'primaryColor': '#1a1a30', 'primaryTextColor': '#e8e4dc', 'primaryBorderColor': '#FFD700', 'lineColor': '#9a968e'}}}%%
sequenceDiagram
  participant U as You
  participant C as Centurion
  participant HC as Hot Cache
  participant SR as Session Recall
  participant V as Vault

  Note over HC: Loaded once at session start
  U->>C: Message
  C->>HC: Essentials already in context
  alt References a past conversation
    C->>SR: session_search
    SR-->>C: Matching messages
  end
  alt Needs long-horizon fact / stores a durable note
    C->>V: search / propose→commit
    V-->>C: Sealed entry (if unlocked)
  end
  C-->>U: Reply
```

## At a glance

| Horizon | What it is | When it's used | You manage it |
|---------|------------|----------------|---------------|
| **① Hot Cache** | `MEMORY.md` + `USER.md` (~1,300 tokens total) | **Every session** — frozen into the system prompt at start | Agent curates via the `memory` tool; you can ask it to remember or forget |
| **② Session Recall** | Full transcript history in `~/.centurion/state.db` | **On demand** — when something from a past chat matters | Automatic storage; agent uses `session_search` to find it |
| **③ Vault** | Encrypted Core / Experiential / Pattern entries | **Deliberately** — long-horizon facts the hot cache cannot hold | Opt-in: `centurion vault init`, unlock, `vault.enabled: true` |

:::tip Day to day
Most users live on **Hot Cache + Session Recall** without configuring anything. Open **Vault** when you want sealed, offline archives that outgrow the tiny always-on card.
:::

---

## ① Hot Cache (always on)

**Files:** `~/.centurion/memories/MEMORY.md` and `USER.md`

The near horizon — a **wallet card** of facts in every session:

- **MEMORY.md** — environment, projects, conventions, lessons learned (~2,200 chars)
- **USER.md** — your preferences, style, identity (~1,375 chars)

The agent adds, replaces, and removes entries with the `memory` tool. Content is scanned for injection patterns before it is saved.

**Frozen snapshot:** Captured once at session start; mid-session writes hit disk immediately but refresh the prompt on the **next** session (keeps prompt caching warm).

→ Full details: [Persistent Memory](./memory.md)

---

## ② Session Recall (on demand)

**Store:** `~/.centurion/state.db` (SQLite + FTS5)

The mid horizon — every CLI and messaging conversation, searchable with `session_search`:

- "Did we discuss the migration last week?"
- Scroll forward/backward inside a found session
- No extra LLM cost for search (FTS5 keyword lookup)

Unlimited capacity, **never** stuffed into every prompt. The agent reaches here when past context is relevant.

→ Full details: [Sessions](../sessions.md#session-search-tool)

---

## ③ Vault (opt-in, encrypted)

**Path:** `{CENTURION_HOME}/vault/` (profile-safe)

The far horizon — **offline sealed long-term memory**. AES-256-GCM at rest, passphrase unlock, no cloud sync:

| Type | Use for |
|------|---------|
| `core` | Stable facts and preferences that outgrew the hot cache |
| `experiential` | Significant events and decisions |
| `pattern` | Recurring workflows ("when X, do Y") |

Writes are always **propose → commit**. Vault never auto-ingests full transcripts (use Session Recall for that). Secrets and transcript dumps are rejected at ingest.

**Default:** `vault.enabled: false`.

```bash
centurion vault init
centurion vault unlock
```

```yaml
# ~/.centurion/config.yaml
vault:
  enabled: true
  prefetch_on_turn: false   # optional per-turn recall; off by default
```

→ Full details: [Vault](./vault.md)

---

## Which horizon for what?

| You want to… | Use |
|--------------|-----|
| Remember a preference or project fact for every chat | **Hot Cache** — `memory` / `user` |
| Find what you said in a conversation two weeks ago | **Session Recall** — `session_search` |
| Archive a durable decision, workflow, or life context for years | **Vault** — `core` / `experiential` / `pattern` |
| Store an API key or credential | **None** — use secrets / env; Memory Horizon layers block credential patterns |

**Division of labor:** Keep Hot Cache **small and essential**. Use Session Recall for **historical chat lookup**. Use Vault for **long-horizon archives**.

---

## Optional: external memory providers

Plugins such as Honcho, Mem0, or OpenViking add a **separate** cross-session recall surface. They run **alongside** Memory Horizon — never replacing the Hot Cache.

→ [Memory Providers](./memory-providers.md)

---

## Related

- [Persistent Memory](./memory.md) — Hot Cache in depth
- [Vault](./vault.md) — Vault setup and threat model
- [Sessions](../sessions.md) — Session Recall and session management
- [Configuration](../configuration.md) — `memory:` and `vault:` config keys
