# Sovereign AI Remote — device smoke checklist

Run on a physical iPhone with Brain **5.3.0+**. **Pair once on home Wi‑Fi**, then
validate Away on **cellular** only after Brain `remote_relay_status` shows
`websockets_installed` + `realtime_pipe_ready` and Chat from anywhere is enabled.

Power-user tunnel/`EXPOSE_9119.md` is **not** the App Store Away path.

## Build / icons

- [ ] `xcodegen generate` then build Release for `com.centurion.ios`
- [ ] App icon 1024 any + dark present; launch screen shows AppMark
- [ ] Display name: **Sovereign AI Remote**; version **5.3.0** / build **45**
- [ ] Portrait only; PrivacyInfo.xcprivacy in app bundle
- [ ] Camera permission string present (`NSCameraUsageDescription` — QR only)

## Pairing & Crypto Chat — QR primary (home)

- [ ] Brain shows QR (GTK **Show pairing QR** / Link iPhone)
- [ ] Phone on **home Wi‑Fi** → Scan QR → Crypto Chat works
- [ ] Paste fallback still works at home
- [ ] Before link: Chat shows **Not linked to a Brain** demo banner (no fake live threads)
- [ ] After successful link, demo content clears (`clearDemoData`)

## LAN topics DoD (required before calling Chat finished)

Mirror of [`brain/linux/docs/REMOTE_RELAY.md`](../../../brain/linux/docs/REMOTE_RELAY.md):

- [ ] Create Mission / Plan / freeform topics from iPhone tray or Home Discuss
- [ ] Switch topics; transcripts do not bleed across contexts
- [ ] Kill app; reopen; tray lists host SessionDB topics with framing restored
- [ ] Desktop sidebar resume restores Discuss banner from `topic_kind` / `topic_ref`
- [ ] Rename / delete topic from iPhone tray (and Desktop sidebar)
- [ ] Mid-turn approval still works on LAN Crypto Chat

## Away (only after LAN green + relay enrolled)

- [ ] Enable Chat from anywhere on Brain + You → Anywhere
- [ ] Phone on **cellular** → Crypto Chat + mid-turn approval over relay
- [ ] Kill app and reopen on cellular; reconnects / re-KX cleanly
- [ ] Brain offline → clear offline honesty
- [ ] Speed: You → **Copy speed soak samples** + `python -m centurion_cli.remote_relay_speed --away …`
- [ ] Privacy Help: You → Anywhere footer / Unbox links *Local, Remote anywhere, or Telegram*

## Mission / Soul / Autonomy / Oversight

- [ ] Open Mission; edit or view Life Mission
- [ ] While linked: **Sync Life Mission to Sovereign** succeeds
- [ ] You → **Your Sovereign's Soul** opens; save syncs to `SOUL.md`
- [ ] You → **Autonomy Level** shows four levels; default Balanced

## Desk ops (You → Brain desk) — glance only

- [ ] Ops / License / Firecrawl respond when linked
- [ ] Skills / Fleet / Plugins / Telegram rows labeled **(glance)** — status only, not full control

## Collaborations

- [ ] You → **Start a collaboration** → **Form** with goal + 2 worker profiles (gateway running)
- [ ] Focus shows the board; block a worker → Needs your choice → **I've decided**
- [ ] Discuss seeds Chat with board framing
- [ ] Join / Invite fields reach Mission Control; a down portal shows an error (no silent empty board)

## Privacy Hub honesty

- [ ] Privacy Hub describes home LAN vs optional Anywhere (E2E content; cloud metadata/presence only)
- [ ] No absolute “zero server metadata” / “no routing server” claims

## Accessibility

- [ ] Dynamic Type on Chat / You / Focus
- [ ] VoiceOver on Chat / You / Focus
- [ ] Primary actions are at least 44pt
