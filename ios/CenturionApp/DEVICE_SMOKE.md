# Sovereign Remote — device smoke checklist

Run on a physical iPhone 15+ (or supported simulator for UI-only checks) against a live Sovereign before TestFlight.

## Build / icons

- [ ] `xcodegen generate` (if used) then build Release for `com.centurion.ios`
- [ ] App icon 1024 any + dark present; launch screen shows AppMark
- [ ] Display name: **Sovereign Remote**; version **5.0.1** / build from `CURRENT_PROJECT_VERSION`
- [ ] Portrait only; PrivacyInfo.xcprivacy in app bundle

## Pairing & Crypto Chat

- [ ] Find Sovereign on home Wi‑Fi (Bonjour)
- [ ] Approve device on Sovereign; link succeeds
- [ ] Send Crypto Chat message; receive reply
- [ ] Kill app and reopen; reconnects to saved endpoint
- [ ] Disconnect / revoke shows clear offline state (no fake “live” success)

## Demo data

- [ ] Before first link, demo banner may appear
- [ ] After successful link, demo conversations clear (`clearDemoData`)

## Mission / Soul / Autonomy / Oversight

- [ ] Open Mission; edit or view Life Mission
- [ ] You → **Your Sovereign's Soul** opens; subtitle reflects sync state when linked
- [ ] Shape Your Sovereign shows save warning; note about next-conversation effect
- [ ] After save while linked, Soul syncs to Sovereign `SOUL.md`
- [ ] You → **Autonomy Level** shows four levels; default Balanced; description updates
- [ ] **Reporting & Oversight** section opens; cadence / confirm / initiative toggles save
- [ ] Changes apply on next conversation (not mid-chat)
- [ ] Commitment chat frames and sends when connected

## Memory Horizon

- [ ] You → **Memory Horizon** opens three cards (Near Hot Cache / Mid Session Recall / Far Vault)
- [ ] While linked, gauges show live fill; Hot Cache subtitle shows MEMORY vs YOU split
- [ ] Session Recall shows conversation count and space on Sovereign (not “RAM full”)
- [ ] Vault shows Off / Locked / Ready honestly (empty gauge when off)
- [ ] Tap a card → sheet with how-to-manage copy and one primary Chat action
- [ ] Primary action seeds Crypto Chat when linked; disabled guidance when offline
- [ ] Offline / not linked: banner “Link your Sovereign to see live memory levels”
- [ ] Learn more opens Help Center Memory Horizon article
- [ ] Desktop Settings → **Memory Horizon** View shows the same live snapshot

## Plans (Propose first + Host sync)

- [ ] Chat shows **Talk** / **Propose first** chips
- [ ] Propose first drafts a plan; Home **Plans** / Needs your choice / Documents show it
- [ ] Live may show “Drafting a plan…” while planning
- [ ] Plan review: **Proceed** / **Adjust** / **Hold** work; Proceed syncs to host when linked
- [ ] Risk badge appears when host classifies the plan
- [ ] **Templates** under Home → Plans instantiate a reviewable plan when linked
- [ ] **Share for review** accepts a reviewer customer id and records reviewers on the plan
- [ ] After reconnect, plans refresh from the Sovereign (host is source of truth)

## Desktop Settings (parity)

- [ ] Settings → Autonomy Level Adjust changes host preference
- [ ] Settings → Your Sovereign's Soul View/Edit saves with warning copy
- [ ] Settings → Reporting & Oversight Adjust saves cadence and toggles
- [ ] Settings → Memory Horizon View refreshes Hot Cache / Session / Vault summary

## Adrian (optional help)

- [ ] Talk to Adrian reaches help.1human1ai.com
- [ ] Reply is help guidance; no Crypto Chat history appears in Adrian

## Swarm (shipped paths)

- [ ] Settings → **Connect another Sovereign** opens join / invite sheet
- [ ] Join with valid project token works when portal configured
- [ ] Invite by customer id reaches Sovereign (error message if not linked is clear)
- [ ] **No** “Start collaboration” formation banner on Chat
- [ ] Pulse attention picker says in-app only (not phone alerts)

## Thinking / recovery

- [ ] With thinking service healthy, chat succeeds
- [ ] Thinking recovery sheet opens from chat error path when applicable

## Regression notes

Record device model, iOS version, Sovereign hostname, and pass/fail date here when run:

```
Date:
Device:
iOS:
Sovereign:
Result:
```
