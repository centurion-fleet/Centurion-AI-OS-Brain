# Sovereign AI Remote — device smoke checklist

Run on a physical iPhone against a live Sovereign **away-from-home**
(cellular or a non-home network). Do **not** treat same-LAN / Bonjour as the
success path. Pair by **scanning the QR** that embeds
`token:…@public-or-tunnel-host:9119` after exposing TCP 9119
(see `brain/linux/docs/EXPOSE_9119.md`).

## Build / icons

- [ ] `xcodegen generate` (if used) then build Release for `com.centurion.ios`
- [ ] App icon 1024 any + dark present; launch screen shows AppMark
- [ ] Display name: **Sovereign AI Remote**; version **5.1.0** / build **28+**
- [ ] Portrait only; PrivacyInfo.xcprivacy in app bundle
- [ ] Camera permission string present (`NSCameraUsageDescription` — QR only)

## Pairing & Crypto Chat (away-from-home) — QR primary

- [ ] Brain shows QR (GTK **Link iPhone — show QR**, or `centurion remote pair --host …`)
- [ ] Phone on **cellular** (not Brain Wi‑Fi) → Connect → **Scan QR** → link succeeds
- [ ] Paste fallback still works (Connect → Paste code instead)
- [ ] Crypto Chat round-trip works after QR link
- [ ] Kill app and reopen still away from home Wi‑Fi; reconnects to saved remote endpoint
- [ ] Disconnect / revoke shows clear offline state (no fake “live” success)
- [ ] Optional only: LAN Bonjour / approve path (secondary; not required for ship)

## Demo data

- [ ] Before first link, demo banner may appear
- [ ] After successful link, demo conversations clear (`clearDemoData`)

## Mission / Soul / Autonomy / Oversight

- [ ] Open Mission; edit or view Life Mission
- [ ] While linked: **Sync Life Mission to Sovereign** succeeds; subtitle shows synced
- [ ] Start a **new** Crypto Chat after sync — Sovereign advances the Life Mission without re-pasting it
- [ ] You → **Your Sovereign's Soul** opens; subtitle reflects sync state when linked
- [ ] Shape Your Sovereign shows save warning; note about next-conversation effect
- [ ] After save while linked, Soul syncs to Sovereign `SOUL.md`
- [ ] You → **Autonomy Level** shows four levels; default Balanced; description updates
- [ ] **Reporting & Oversight** section opens; cadence / confirm / initiative toggles save
- [ ] Changes apply on next conversation (not mid-chat)

## Memory Horizon / Plans / Thinking Service

- [ ] Memory Horizon live gauges while linked
- [ ] Propose first → plan decide (Proceed / Adjust / Hold / Discuss) syncs to host
- [ ] Thinking Service catalog / apply / routing while linked

## Gateway control (essential)

- [ ] You → Messaging gateway shows Running/Stopped from host
- [ ] Start / Stop / Restart from phone updates host gateway
- [ ] Toggle a platform enabled/disabled; restart applies

## Durable sessions (essential)

- [ ] Crypto Chat returns/stores a host `session_id`
- [ ] New chat creates a distinct host session
- [ ] Resume / continuity after kill-app + reconnect away from home

## Tool approvals (essential)

- [ ] Autonomy set below Max (Balanced) with confirm-dangerous on
- [ ] Trigger a dangerous tool from Crypto Chat
- [ ] Phone shows approval card (Approve once / session / always / Deny)
- [ ] Approving continues the turn; Deny blocks without silent auto-approve

## Adrian / Swarm / Support

- [ ] Talk to Adrian reaches help.1human1ai.com (optional)
- [ ] Connect another Sovereign join/invite paths still clear when linked
- [ ] Get Help / support bundle while linked
