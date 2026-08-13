# E2E matrix: provider switch and recovery

Manual verification checklist for Terminal-Free Provider Management.

## Prerequisites

- `centurion-remote` running on host (port 9119)
- iPhone on same LAN, device approved
- At least one valid API key in `~/.centurion/.env`

## Host control plane (Phase 1)

- [ ] `centurion provider status --json` returns `ok: true` and `status.health`
- [ ] `centurion provider options --json` lists authenticated providers
- [ ] `centurion provider validate <provider> <model> --json` succeeds for current config
- [ ] `centurion provider set <provider> <model> --json` updates `config.yaml`
- [ ] `centurion provider restore --json` restores after a deliberate bad switch
- [ ] `~/.centurion/state/last_good_model.json` created after successful probe/chat
- [ ] Dashboard `POST /api/model/set` (main scope) uses control plane (no raw YAML-only path)

## Remote protocol (Phases 2–3)

- [ ] iPhone chat error shows thinking-service banner (not endless spinner)
- [ ] Error `code` is `LLM_*` (not only `CENTURION_UNAVAILABLE`) for LLM failures
- [ ] iPhone Connect tab: device link and thinking service shown separately
- [ ] iPhone Settings → Advanced: live provider list from host
- [ ] iPhone recovery sheet: validate, apply, restore LKG

## GTK desktop (Phase 4)

- [ ] Home tab shows thinking service line under device status
- [ ] Settings → Your Centurion's thinking shows provider/model/health
- [ ] Restore last working setup button works

## Self-heal (Phase 5)

- [ ] Bad model switch + existing LKG → remote bridge auto-restores once and retries chat
- [ ] User sees recovery message when auto-restore succeeds

## Gateway (Phase 6)

- [ ] `/model sonnet --global` persists via `commit_switch_result`
- [ ] Docs: `website/docs/user-guide/features/provider-recovery.md`

## Provider swap scenarios

| From | To | Surface |
|------|-----|---------|
| OpenRouter | DeepSeek | iPhone Settings |
| DeepSeek | Claude (OpenRouter) | GTK restore + set |
| Any | Invalid model | Chat error + Fix sheet |
| Any | Missing API key | `LLM_AUTH_MISSING` + host key flow |
