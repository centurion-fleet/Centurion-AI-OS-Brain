# Customer cutover — Brain + Remote (3-hour window)

**Brain tag:** `v5.2.54`  
**Remote:** Sovereign AI Remote **5.1.0** (build **29**)  
**Do not ship:** dirty license/fleet/billing WIP; pairing/Unbox redesign; iOS bump to 5.2.x

---

## What customers get

| Surface | Ready |
|---------|--------|
| Brain Chat / Home (6 pills) / Settings | Yes |
| Home = pulse only (mission, commitments, orbs, pills/feed) | Yes |
| Desk ops moved to Settings (fleet, plugins, cron/board, Connect, mission edit) | Yes |
| Plan / Decision / Commitment / Horizon discuss | Yes |
| Last-seen “· N new” pills | Yes |
| Thinking, Horizon gauges, Gateway, Support/Adrian | Yes |
| Same-Wi‑Fi QR pair → phone Crypto Chat | Yes (smoke required) |
| Away-from-home / Unbox product work | Frozen — existing path only |

---

## Host install (each Linux Brain)

```bash
cd ~/Centurion-AI-OS   # or customer checkout path
git fetch --tags origin
git checkout v5.2.54
# Keep working tree free of unrelated WIP for this install
desktop-native/scripts/install-user.sh
```

Then:

1. Quit and reopen **Sovereign AI Brain** (restart after install).
2. Confirm title/about shows **5.2.54**.
3. Chat: send one message; confirm reply.
4. Home: mission/commitments/orbs + pills — **no** Fleet / Extensions / Scheduled & board / Connect chrome.
5. Settings → Life Mission / Mission Discovery / Collaborations / Fleet peer / Scheduled & board / Installed plugins.
6. Settings → Thinking: provider visible; Status: pairing QR available.

**Rollback:** `git checkout v5.2.53` (or last known-good install) + re-run `install-user.sh`. Do **not** merge dirty WIP to “fix forward.”

---

## Phone smoke (Remote ≥ 5.1.0 build 29)

1. Confirm App Store / TestFlight version **5.1.0 (29)**.
2. Same Wi‑Fi as Brain → scan Status QR → approve device on Brain.
3. Phone Chat round-trip.
4. Phone: Plan or Decision → Discuss / Proceed path once.
5. Optional: commitment chip / Horizon discuss; pill badges clear on visit.

Away-from-home: advertise host / tunnel **9119** per install notes — no new relay code this window.

---

## Ops freeze list

- No Unbox / pairing / relay feature work  
- No committing `centurion/license/`, fleet billing WIP, or `build/` into this cut  
- No iOS marketing bump to 5.2.54 for lockstep optics  

---

## Product note (v5.2.54)

Brain Home matches iPhone pulse: management chrome (fleet, plugins, ops glance, Connect, mission Edit/Discover) lives under **Settings**, not Home.
