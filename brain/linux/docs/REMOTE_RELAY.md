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
| iPhone away `RelayAwayClient` when LAN down | Done (pipe + presence; full chat tunnel over Realtime still soak-tested in Away DoD) |
| Help privacy tiers linked (Settings + Unbox) | Done |
| Live Supabase websocket against production project | Ops: enroll project + set Vercel env |
| Away DoD / App Store “anywhere” copy | **Gated** until Away DoD passes |

LAN `:9119` Crypto Chat remains preferred whenever reachable.

## TestFlight path (LAN topics first)

1. Brain package at tip **5.2.137+** with this branch merged.
2. iPhone TestFlight build marketing **5.2.137** (lockstep).
3. Pair on home Wi‑Fi (Unbox QR) — no home IP typed.
4. Run **LAN topics DoD** below before claiming topic continuity.
5. Optionally enable Settings → Anywhere (Desktop) / You → Chat from anywhere (iPhone) for internal relay soak — **do not** use App Store “works anywhere” wording until Away DoD is green.

## LAN topics DoD (ships before away)

- [ ] Create Mission / Plan / freeform topics from iPhone tray or Home Discuss
- [ ] Switch topics; transcripts do not bleed across compressed contexts
- [ ] Kill app; reopen; tray lists host SessionDB topics with framing restored
- [ ] Desktop sidebar resume restores Discuss banner from `topic_kind` / `topic_ref`
- [ ] Rename / delete topic from iPhone tray context menu (and Desktop sidebar)
- [ ] Mid-turn approval still works on LAN Crypto Chat (unchanged path)

## Away-over-relay DoD (gates App Store “anywhere”)

- [ ] Pair once at home; enable Chat from anywhere on Brain
- [ ] Leave Wi‑Fi; same topics list and resume over RelayTransport
- [ ] Brain offline → clear failure (same honesty as Telegram gateway down)
- [ ] Reconnect mid-turn → retryable error; no half-delivered approvals
- [ ] Chunked history resume >180KB succeeds; oversize soft-fails cleanly
- [ ] Privacy Help article linked from Settings / Unbox

## Customer help

Help Center: *Local, Remote anywhere, or Telegram — privacy choices*
(`privacy-and-security/local-remote-telegram-privacy`).
