# Sovereign AI Remote — TestFlight What to Test (build 43)

**iOS App Version 5.2.151** (not 5.0.1). Build **43**.

## You tab (5.2.151)

- Linked: the first card is **You** — Mission, Soul, Autonomy. Not Connect, not Family & friends.
- Family & friends is a sub-menu, lower in the list.
- Connect / This Brain are below Family & friends.
- Brain Settings uses the same group names in the same order.

## Crypto Chat (5.2.150)

- Pair on home Wi‑Fi. Chat should say **Loading mission data. Please wait.** and keep the composer locked until that finishes.
- Then stay on Chat and send one `Hi`. Expect a spoken reply (not a hang on “Waiting on your Sovereign”).
- Do not open Focus until that reply lands. Green lock during the wait is pairing, not Chat ready.

## Focus / Missions (5.2.148)

- Middle tab is **Focus** (not Home).
- Pulse pill is **Missions** (not Plans). Same reviewable work as Brain.

## Paper & bronze (5.2.147)

- Light: warm paper (`#FAFAF9`) + bronze accent (`#433830`) — no blue tabs.
- Dark: warm near-black (`#110C09`) + pale bronze PulseDot (`#D3CDBF`).
- One bright accent per screen (avatar / active / primary CTA).

## Honesty (5.2.145)

- Privacy Hub: home Wi‑Fi vs Chat from anywhere (E2E content; cloud metadata only).
- Collaborations: **Start a collaboration** = local board only (no portal invite).
- Brain desk: Skills / Fleet / Plugins / Telegram are **glance** (status only).
- Unlinked Chat: **Not linked to a Brain** banner — no fake live threads.

## LAN topics DoD

On home Wi‑Fi after pairing:

1. Create Mission / Plan / freeform topics from the tray.
2. Switch topics — no transcript bleed.
3. Kill and reopen app — tray restores host topics.
4. Rename / delete from iPhone; confirm Desktop sidebar.
5. Mid-turn approval still works.

## Away (internal soak only)

Enable Chat from anywhere on the Brain first. Cellular Crypto Chat + mid-turn approval.
Do **not** treat App Store “works anywhere” as unlocked until Away DoD in `REMOTE_RELAY.md` is green.
