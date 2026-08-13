# Sovereign AI Remote — device smoke checklist

Run on a physical iPhone. **Pair once on home Wi‑Fi**, then validate Away on
**cellular** with **Chat from anywhere** enabled on the Brain (no DIY expose of
TCP 9119). Pair by **scanning the QR** shown on the Centurion (paste fallback OK).

Power-user tunnel/`EXPOSE_9119.md` is **not** the App Store Away path.

## Build / icons

- [ ] `xcodegen generate` (if used) then build Release for `com.centurion.ios`
- [ ] App icon 1024 any + dark present; launch screen shows AppMark
- [ ] Display name: **Sovereign AI Remote**; version **5.2.137** / build **30+**
- [ ] Portrait only; PrivacyInfo.xcprivacy in app bundle
- [ ] Camera permission string present (`NSCameraUsageDescription` — QR only)

## Pairing & Crypto Chat — QR primary (home), then Away

- [ ] Brain shows QR (GTK **Link iPhone — show QR**)
- [ ] Phone on **home Wi‑Fi** → Scan QR → Crypto Chat works
- [ ] Enable Chat from anywhere on Brain + You → Anywhere
- [ ] Phone on **cellular** (not Brain Wi‑Fi) → Crypto Chat + mid-turn approval over relay
- [ ] Kill app and reopen on cellular; reconnects / re-KX cleanly
- [ ] Brain offline → clear offline honesty (no fake “live” success)
- [ ] Paste fallback still works at home

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

## Desk ops (You → Brain desk)

- [ ] Ops glance / License / Firecrawl / Skills / Fleet / Plugins / Telegram preview respond when linked

## Speed (optional soak)

- [ ] Home Wi‑Fi ping feels instant; Away first-token wait shows activity / not a hung spinner
