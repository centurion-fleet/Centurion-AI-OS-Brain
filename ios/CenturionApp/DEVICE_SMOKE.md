# Sovereign Remote — device smoke checklist

Run on a physical iPhone 15+ (or supported simulator for UI-only checks) against a live Sovereign before TestFlight.

## Build / icons

- [ ] `xcodegen generate` (if used) then build Release for `com.centurion.ios`
- [ ] App icon 1024 any + dark present; launch screen shows AppMark
- [ ] Display name: **Sovereign Remote**; version **5.0.0** / build from `CURRENT_PROJECT_VERSION`
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

## Mission / Soul

- [ ] Open Mission; edit or view Life Mission
- [ ] Soul Document / interview paths open without crash
- [ ] Commitment chat frames and sends when connected

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
