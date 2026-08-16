# Centurion Remote relay (Vercel + Supabase)

Product path for **Chat from anywhere** — not DIY Tailscale/Cloudflare.

## Roles

| Piece | Job |
|-------|-----|
| **Supabase Realtime** | Long-lived Brain↔phone pipe; private channel `brain:{install_id}` |
| **Supabase Postgres** | `remote_brain_installs`, `remote_pair_tokens`, presence ([SQL](./remote-relay-supabase.sql)) |
| **Vercel** | HTTPS control plane: enable / pair / revoke / health (service role) |
| **Brain `RelayTransport`** | Outbound Realtime; chunked E2E envelopes; reconnect = full re-KX |
| **iPhone** | LAN Crypto Chat at home; RelayTransport away after pair |

LAN TCP `:9119` Crypto Chat stays unchanged.

## Envelope (Realtime event)

```json
{
  "v": 1,
  "conn": "<epoch-after-each-reconnect>",
  "id": "<uuid>",
  "kind": "kx_client|kx_server|frame|frame_chunk",
  "chunk_i": 0,
  "chunk_n": 1,
  "body_b64": "<nonce||ciphertext or raw KX bytes>"
}
```

Rules: reassemble chunks before decrypt; new Realtime socket ⇒ new `conn` ⇒ re-KX; match responses by `id`; never reuse session keys across reconnects.

## Privacy (customer language)

See Help Center: *Local, Remote anywhere, or Telegram — privacy choices*.

- **Local / home Wi‑Fi** — strongest for chat transport content  
- **Remote via this relay** — E2E content; metadata through Centurion cloud  
- **Telegram** — Telegram can see message content  

## Status

| Piece | State |
|-------|--------|
| Envelope + chunking + id-demux (`centurion_cli/relay_transport.py` + iOS `RelayTransport.swift`) | Done |
| Brain control (`remote_relay_service` + bridge `remote_relay_*`) | Done |
| Supabase schema + RLS | Done (`remote-relay-supabase.sql`) |
| Vercel enable/pair/revoke/health | Done — scaffold in `cloud/remote-relay/`; staged to sales site `app/api/remote-relay/` |
| iPhone prefer-LAN / You → Anywhere toggle | Done |
| Desktop Settings → Chat from anywhere | Done |
| Brain outbound presence + Realtime client | Done (`remote_relay_realtime.py` singleton pump) |
| Brain Realtime → localhost `:9119` Crypto Chat splice | Done (`remote_relay_splice.py`) |
| iPhone Away Crypto Chat (KX + frames + approvals over Realtime) | Done (`RelayAwayClient` + `ConnectionManager` transport mux) |
| iPhone everyday surfaces gate on `isCryptoChatReady` (LAN or Away) | Done (stores/Settings/Home/Chat/Help) |
| Mid-turn activity frames Brain→phone (tool/thinking/status) | Done (`BridgeTurnEvent::Activity` + `RemoteMessage::Activity`) |
| Mid-turn assistant `stream_delta` frames Brain→phone | Done (coalesced deltas + iPhone live draft bubble) |
| Away offline honesty (Brain down → clear iPhone/Desktop error) | Done |
| Generic BridgeAction passthrough (desk ops / remote_relay_*) | Done (`centurion-common` / `centurion-remote`) |
| Help privacy tiers linked (Settings + Unbox) | Done |
| Live Supabase websocket against production project | Ops: enroll project + set Vercel env; `websockets` ships via `[all]` / `[remote-relay]` |
| Away DoD / App Store “anywhere” copy | **Gated** until Away DoD checklist below is green on cellular + CGNAT |
| `remote_relay_status` reports `websockets_installed` / `realtime_pipe_ready` | Done |

LAN `:9119` Crypto Chat remains preferred whenever reachable.

### Speed budgets (Workstream C)

Instrument on device (`lastTransportRttMs` / `lastTtftOverheadMs`) and Brain logs (no PII):

| Metric | LAN | Away |
|--------|-----|------|
| Transport RTT (ping) | p50 &lt; 50ms, p95 &lt; 150ms | p50 &lt; 200ms, p95 &lt; 500ms |
| Transport overhead on first UI token | &lt; 100ms p95 | &lt; 400ms p95 |
| Cold Anywhere connect + re-KX | N/A | &lt; 3s p95 |

Warm Realtime while Anywhere is enabled; one KX per `conn` epoch; stream frames immediately (no batch-until-complete).

### Soak / speed smoke (no PII)

Evaluate recorded samples against the budgets above (fixture only — does not hit the network):

```bash
# Green demo (LAN + Away synthetic samples)
python -m centurion_cli.remote_relay_speed --demo

# Print Away DoD checklist (gates App Store “anywhere”)
python -m centurion_cli.remote_relay_speed --checklist
python -m centurion_cli.remote_relay_speed --checklist --status

# Paste device/Brain soak samples (ms, comma-separated)
python -m centurion_cli.remote_relay_speed --away \
  --rtt 120,150,180,190 \
  --ttft 220,310,390 \
  --cold 1800,2200,2600

# Doctor Away readiness (when Chat from anywhere is enabled)
centurion doctor
```

Instrument on device: Settings → Chat from anywhere → **Copy speed soak samples**
(builds a ready `python -m centurion_cli.remote_relay_speed …` command from rolling RTT / TTFT / cold-connect samples; no PII). Markers: `lastTransportRttMs`, `lastTtftOverheadMs`, `lastColdConnectMs`, `lastApprovalAppearMs`.

Brain: `remote_relay_status` → `websockets_installed`, `realtime_pipe_ready`.

Away history soft-fail: clients pass `limit` on `session_resume`; Brain may return `truncated: true`. Oversize frames surface as clear iPhone copy (home Wi‑Fi), not a silent hang.

Mid-turn reconnect: Realtime drop fails the in-flight turn with retryable copy (`turnInterrupted` / `RELAY_RECONNECT`), clears the phone-side approval sheet, and re-enters Away KX — no silent hang.

## TestFlight path (LAN topics first)

1. Brain package at tip **5.2.152+** with this branch merged.
2. iPhone TestFlight build marketing **5.2.152** / build **44** (lockstep).
3. Pair on home Wi‑Fi (Unbox QR) — no home IP typed.
4. Run **LAN topics DoD** below before claiming topic continuity.
5. Optionally enable Settings → Anywhere (Desktop) / You → Chat from anywhere (iPhone) for internal relay soak — **do not** use App Store “works anywhere” wording until Away DoD is green.

### Desk enrollment (ops)

```bash
# Away deps (Brain venv)
uv pip install 'centurionai-os[remote-relay]'   # websockets + pynacl
# Then configure remote_relay.supabase_url + anon/service key (Centurion project)
# Confirm: python -m centurion_cli.remote_relay_speed --status
# Expect: websockets_installed=true, supabase_url_configured=true, realtime_pipe_ready when enabled+online
```

Until `supabase_url` is configured on the production desk, Away DoD cannot go green.

## LAN topics DoD (ships before away)

- [ ] Create Mission / Plan / freeform topics from iPhone tray or Home Discuss
- [ ] Switch topics; transcripts do not bleed across compressed contexts
- [ ] Kill app; reopen; tray lists host SessionDB topics with framing restored
- [ ] Desktop sidebar resume restores Discuss banner from `topic_kind` / `topic_ref`
- [ ] Rename / delete topic from iPhone tray context menu (and Desktop sidebar)
- [ ] Mid-turn approval still works on LAN Crypto Chat (unchanged path)

## Away-over-relay DoD (gates App Store “anywhere”)

Code path for Crypto Chat over Realtime is implemented (Brain splice + iPhone mux). Ops still must soak:

- [ ] Pair once at home; enable Chat from anywhere on Brain (`websockets` + Supabase env)
- [ ] Leave Wi‑Fi; same topics list and resume over RelayTransport
- [ ] Mid-turn tool approval over Away
- [ ] Brain offline → clear failure (same honesty as Telegram gateway down)
- [ ] Reconnect mid-turn → retryable error; no half-delivered approvals
  (code: `RelayError.turnInterrupted` clears phone approval UI + re-KX)
- [ ] Chunked history resume >180KB succeeds; oversize soft-fails cleanly
  (code: `session_resume` `limit` + Brain soft size fit + iPhone `payloadTooLarge` copy)
- [ ] Speed budgets green (see table + soak CLI / iPhone **Copy speed soak samples**) on cellular
- [ ] Privacy Help article linked from Settings / Unbox

Until this checklist is green, App Store marketing must not claim “works anywhere” as a finished guarantee — review notes already describe the relay product path (not DIY `:9119`).

**P4 unlock:** only after the Away DoD checklist is green on cellular + CGNAT. Do not flip App Store “anywhere” copy in-repo until then.

## Customer help

Help Center: *Local, Remote anywhere, or Telegram — privacy choices*
(`privacy-and-security/local-remote-telegram-privacy`).
