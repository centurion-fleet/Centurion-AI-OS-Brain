# Sovereign AI Remote — TestFlight What to Test (build 69)

**iOS App Version 5.4.0**. Build **69**. Pair against this Brain.

## 5.4.0 — build 69

- **Connection failures now say why.** A failed link shows the Brain's own reason
  under **NOT LINKED** — pairing code rejected, host unreachable, or the
  Centurion's key has changed — with **Try again** and **Pair**.
- **Changed Centurion identity is recoverable.** If the Brain was rebuilt or
  restored, the card offers **Trust this Centurion again** instead of a dead end.
- Fixes the handshake send that made builds 64–67 uncompilable.

## 5.4.0 — Signum chat surface

The app is now one screen: the conversation, the composer, and the name of your
Centurion. The five-tab dashboard is still in the binary behind the
`signum.chatSurface` flag but is no longer the default.

- **Link** — header is tappable while unlinked: tap the name/status to open
  pairing. The pairing cover dismisses itself the moment Crypto Chat links, and
  the header shows **CONNECTED · THIS MACHINE**.
- **Chat** — send a message, watch the working line ("Reading…", "Running a
  tool…") and the answer stream in. Long-press any message to copy; long-press
  an answer for **Ask again**.
- **Stop** — while a turn is running the send arrow becomes a stop square. Stop
  drops the wait without showing an error card.
- **Try again** — a failed send shows one error card with a retry. Retry
  re-sends the same question without leaving a duplicate in the thread.
- **Conversations** — the menu button opens the drawer. It now pulls the Brain's
  real topic list on open, resumes the Brain session when you pick a topic, and
  long-press → **Delete conversation** removes it on the phone and on the Brain.
- **Name** — the header name comes from the Soul (`name`), cached so the screen
  opens with the right name before the network answers.

Pair on home Wi‑Fi. If pairing times out, check Local Network permission and
delete/reinstall to clear a stale saved endpoint.

## 5.3.8

- **Focus Decisions needed — Proceed / Adjust / Hold actually run.** Pair with this Brain.
  - **Proceed** records the choice, leaves the list, and tells the Brain to continue. Stay on Focus.
  - **Adjust** opens Chat on that decision’s thread and sends the change request so the Brain replies. The item stays in Decisions needed.
  - **Hold** parks the item with a confirmation. No Chat.
- The bubble on the card is still “talk without choosing.”

## 5.3.7

- **Focus Proceed actually resolves the decision** on the Brain. Pair with this Brain — earlier builds opened Chat or missed the host id, so Decisions needed never cleared.
- Focus tab opens the homepage (decisions list), not a supporting mission. Mission **Done** fires on press (WebKit was eating the tap).

## 5.3.6

- **Chat from anywhere enrolls with Centurion cloud.** Settings → Anywhere On fetches health, registers this Brain, and publishes presence. Pair on home Wi‑Fi first; Away uses 1human1ai.com + Supabase Realtime when LAN is gone.
- If enable cannot reach the cloud, GTK and iPhone show the error instead of a silent “On — waiting”.
- Cellular soak still required before Away DoD is green (`REMOTE_RELAY.md`).

## 5.3.5

- Brain **Form swarm** actually creates the board (goal stays until the Kanban appears). Pair with this Brain — 5.3.4 cleared the goal and stayed on the empty form.
- Form no longer waits on inline worker dispatch (gateway picks workers up). Button shows **Forming…** and errors land in the amber banner.

## 5.3.4

- Brain **Collab** is Kanban (or first-run Form swarm), not Focus. Pair with this Brain build.
- Focus tab badge is **Decisions needed** (full outstanding count). Collab tab badge is **new since you last opened Collab**.
- Phone Collab is still orbs + goal + Form swarm.

## 5.3.3

- Tabs are **Chat | Focus | Collab | You**. Collab sits between Focus and You.
- **Phone stays orbs. Desk gets Kanban.** Same swarm, two surfaces.
- Collab first-run: write a **goal** (what this swarm should produce now), then Form. Gateway can be started from the tab if it is down.
- Waiting / attention / blocked swarm counts badge **Collab**, not Focus.
- You hub **Open** / **Start a collaboration** opens the Collab tab. Join or invite is under Advanced (Mission Control).
- Focus Missions pill is still reviewable **Plans**. Life Mission is the why; Form swarm does not copy a Focus plan.
- Away remains internal soak until `REMOTE_RELAY.md` Away DoD is green.

## 5.3.2

- **Proceed actually continues.** From Focus list or plan detail, Proceed sends Chat so the Brain keeps working. The item leaves **Decisions needed**.
- Brain Focus has the same **Review / Proceed / Adjust / Hold** as the phone.
- Pulse copy is **Decisions needed** (not “Needs your choice” / “Needs review”).
- Logging a decision on a waiting item records that choice in place and stays on the mission as history.
- Mission detail shows **that mission’s documents only**. Focus home lists **all documents** across missions.
- Orange “couldn’t load” banner means the Brain life-stack call timed out (often Chat using the line). Tap the hero card to retry.

## 5.3.1

- Brain You: **Pair Remote** on the hub, Connect **Open** / **Show QR** — pairing is reachable even if a hub row click is swallowed.
- Focus: landing vs detail contrast. **Back to Focus** is a full-width control, not a tiny chevron. Supporting missions are larger on Focus and Mission stack.
- Attention counts are bronze circular badges (not `(N)` in brackets, not red).
- Nominate family + colleague leads sync to DrivenAction / GoHighLevel when the Brain has GHL keys.

## 5.3.0

- You hub rows on Brain open (chevron). Reporting & Oversight dialogs are readable.
- After link, Focus pills (Finished / Documents / Decisions needed / Updates) load after Missions.
- Chat: live reply in the transcript; quiet wait under the composer; thinking tokens stay off-screen.
- Collaborations: **Form swarm** with two worker profiles. Join / Invite via Mission Control. Portal down → error, not an empty board.
- Away remains internal soak until `REMOTE_RELAY.md` Away DoD is green.

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
- Collaborations: Form / Join / Invite — portal errors are visible.
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
