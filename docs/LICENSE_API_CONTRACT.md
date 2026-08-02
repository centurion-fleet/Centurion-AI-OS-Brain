# Brain license API contract (OS follow-on)

Canonical copy lives on the sales site:

`/-personal-centurion-website-v5/docs/LICENSE_API_CONTRACT.md`

Website is source of truth for activate/check payloads until enforcement ships.

Quick rules for Brain clients:

1. Activate with real `hardware_id` / `machine_fingerprint` — never `web-*`.
2. Prefer `next_check_by_unix` over ISO `next_check_by`.
3. Map website `state` via `centurion.license.states.parse_state` (`owned` → `outright_owned`, `grace`, `expired`, …).
4. Desktop Activate uses `tier: "code"` (server decides level).
5. Keep `license.enforcement` opt-in until commercial cutover.
