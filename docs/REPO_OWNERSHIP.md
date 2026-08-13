# Centurion v5 product ownership (OS monorepo note)

Full map lives with the sales site: see website-v5 `docs/REPO_OWNERSHIP.md` and `docs/DNS_CUTOVER.md`.

This monorepo owns:

| Area | Path |
|------|------|
| Centurion AI OS (Brain runtime) | repo root (`agent/`, `centurion_cli/`, `gateway/`, …) |
| Brain hosts | `brain/` (`linux/` shipping, `macos/` roadmap, `service/`, `web-dashboard/`) |
| Phone remotes | `remote/` (`ios/` shipping, `android/` roadmap) |
| Shared client assets | `shared/` (design-tokens, protocol docs, VERSIONING) |

Help owns: Adrian. Website-v5 owns: marketing + commerce. Product API host owns: `/api/v1` fleet/keys/swarm.

Design tokens: `shared/design-tokens/tokens.json` (synced from sales site).
Version lockstep: `shared/VERSIONING.md`.
