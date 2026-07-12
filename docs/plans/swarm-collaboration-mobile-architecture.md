# Swarm Collaboration: Brain and Remote Architecture

## Principle

Centurion frees humans to be in the world. The Linux Centurion Brain runs the
work; Centurion Remote gives the human everything needed to understand, decide,
receive, steer, and form collaborations while away from the desk.

Remote is not a smaller project-management app. It is a mission cockpit:

- orient around what matters now;
- decide when human judgment is needed;
- receive finished documents and outcomes;
- discuss with the right context carried back to the Brain;
- form new collaborations from conversation;
- stay grounded in the human's Life Mission.

## Product Split

| Surface | Responsibility | Collaboration depth |
|---------|----------------|---------------------|
| Linux Centurion Brain App | Runs remote service, approvals, thinking health, full chat/TUI, local storage | Owns state and execution |
| Dashboard `/mission` | Operator/admin mission view | Drill-in, portal sync, kanban-facing detail |
| iPhone Remote | Mobile mission progress | Ambient constellation, Signals, outcomes, contextual chat |

The Remote may feel rich, but its richness comes from the Brain's data. It
stores only preferences and transient render cache.

## Data Residency

Canonical collaboration state lives under the human's active `CENTURION_HOME`.

| Data | Owner | Remote access |
|------|-------|---------------|
| Swarm registry / summaries | Brain | `swarm_snapshot` DTO |
| Local task graph | kanban board DB | summarized only |
| Portal project | `SwarmMcClient` via `mc.json` | projected through Brain |
| Workspace files | collaboration workspace | artifacts/outcomes only |
| Signals | kanban blocked rows / ceremonies | human-facing Signals only |
| Digest mode / last-seen timestamps | iPhone | local preference |

The iPhone must not hold canonical swarm lists, task rows, raw workspaces, portal
tokens, or project files.

## Isolation Model

Centurions share data only inside one collaboration boundary:

1. **LAN-local collaboration:** one kanban board. Workers are spawned with
   `CENTURION_KANBAN_BOARD`, so their tools read only that board.
2. **Portal collaboration:** one `ctk_proj_*` project token. Cross-install
   sharing is limited to that portal project.
3. **Workspace:** one workspace path for collaboration files. Remote receives
   outputs, not raw paths.
4. **Memory/chat:** future swarm-aware conversations must carry `swarm_id` or
   board slug so memory lookup is scoped before broader mission context is
   added.

Sharing allowed inside the boundary: task comments, outcomes, artifacts, Signals,
and workspace outputs. Sharing not allowed by default: other boards, unrelated
portal projects, other workspaces, unrelated memories, or unrelated chat context.

## Remote Protocol

The encrypted LAN protocol exposes a slim collaboration read path:

- `swarm_snapshot` request from iPhone
- `swarm_snapshot_response` with:
  - `swarms`
  - `signals`
  - `outcomes`
  - `activities`
  - portal projection fields when available

The snapshot is produced by `centurion_cli.swarm_state`, not by the iPhone. The
same service backs dashboard `/api/swarm/sync` so mobile and dashboard views do
not drift.

## Mobile Capability Matrix

| Human need while mobile | Remote affordance | Brain source |
|-------------------------|-------------------|--------------|
| Orient | Home constellation + Pulse badges | `swarm_snapshot.swarms` |
| Decide | Signal detail + one CTA | blocked/ceremony projection |
| Receive | Ready outcomes/documents | artifacts/task results |
| Steer | Discuss from collaboration | future swarm-scoped chat context |
| Form | one-screen confirmation | future Brain-side board/project creation |
| Ground | mission line in detail | `mission_id` / Life Mission |

## Implementation Status

Completed:

- documented Brain vs Remote rules in `ios/CenturionApp/DESIGN_RULES.md`;
- added `centurion_cli.swarm_state.get_swarm_snapshot()`;
- moved dashboard `/api/swarm/sync` to the Brain snapshot service;
- added `swarm_snapshot` to the encrypted native Remote protocol;
- updated iOS `SwarmStore` to read snapshot state from the connected Centurion
  and clear legacy phone-owned swarm persistence.

Next:

- make formation confirmation create a Brain-side board/project instead of a
  transient local preview;
- add swarm-scoped chat contexts (`collaboration`, `signal`, `outcome`);
- resolve Signals back to kanban/ceremony source rows;
- fetch full artifact content for mobile document reading;
- add push notification delivery for open human Signals.
