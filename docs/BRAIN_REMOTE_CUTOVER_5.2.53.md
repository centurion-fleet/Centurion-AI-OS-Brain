# Customer cutover — Brain + Remote (3-hour window)

**Brain tag:** `v5.2.53`  
**Remote:** Sovereign AI Remote **5.1.0** (build **29**)  
**Do not ship:** dirty license/fleet/billing WIP; pairing/Unbox redesign; iOS bump to 5.2.x

---

## What customers get

| Surface | Ready |
|---------|--------|
| Brain Chat / Home (6 pills) / Settings | Yes |
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
git checkout v5.2.53
# Keep working tree free of unrelated WIP for this install
desktop-native/scripts/install-user.sh
```

Then:

1. Quit and reopen **Sovereign AI Brain** (restart after install).
2. Confirm title/about shows **5.2.53**.
3. Chat: send one message; confirm reply.
4. Home: pills load; open **Needs your choice** or a Plan.
5. Settings → Thinking: provider visible.
6. Settings → Status: pairing QR available.

**Rollback:** `git checkout v5.2.49` (or last known-good install) + re-run `install-user.sh`. Do **not** merge dirty WIP to “fix forward.”

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
- No iOS marketing bump to 5.2.53 for lockstep optics  

---

## Compile note (v5.2.53)

Upstream includes collab Resolve refresh E0382 + Decision Adjust pid fix: clone `pid` before the `on_ok` / `decide_plan` split (E0382), plus Horizon `vault_status` borrow hygiene. Ships_AI should `git checkout v5.2.53` and install **without** local patches.
