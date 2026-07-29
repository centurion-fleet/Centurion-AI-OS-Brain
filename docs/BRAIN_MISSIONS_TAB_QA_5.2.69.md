# QA Report for Titus — Brain Missions tab (v5.2.69)

**Date:** 2026-07-29  
**Brain tag:** `v5.2.68` → **`v5.2.69`** (this cut)  
**Remote App Store:** no bump  
**Owner ask:** Replace Home with first-class **Missions** tab (stack + pulse); unbury Mission Stack from Settings text dialog  

---

## What this cut is for

| Before | After |
|--------|--------|
| Tabs: Chat · **Home** · Settings | Tabs: Chat · **Missions** · Settings |
| Mission Stack buried under Settings → Open (read-only text dialog) | Interactive Mission Stack on **Missions** (Primary / Supporting / Dreams / Subjects) |
| Pulse lived on Home only | Pulse stays **below** the stack on Missions |
| Settings held the only stack surface | Settings keeps **Edit** + **Mission Discovery**; Mission Stack row → **Open tab** |

Out of scope (Day 2): Activity Hub firehose as default tab.

---

## Install — Brain (Titus / Linux host)

```bash
cd ~/Centurion-AI-OS
git fetch --tags origin
git checkout v5.2.69
desktop-native/scripts/install-user.sh
```

Quit and reopen **Sovereign AI Brain** — About should show **5.2.69**.

**Or** Settings → Check for update → Update now (from a Brain still on 5.2.68).

**Rollback:** `git checkout v5.2.68` + re-run `install-user.sh`.

---

## QA checklist

### A. Three tabs only

1. Open Brain.
2. Confirm bottom/side tabs are **Chat · Missions · Settings** — no **Home**.
3. Default tab is still **Chat**.

**Pass if:** only those three names; Home is gone.

### B. Missions shows stack without Settings burial

1. Open **Missions**.
2. Expect header **Missions** + subtitle about what you’re building toward.
3. Expect **MISSION STACK** with Primary (or empty CTA pointing at Settings → Mission Discovery).
4. Supporting / Dreams / Subjects appear when data exists.
5. Pulse (commitments, collaboration orbs, pills, working-on / needs-choice / finished) appears **below** the stack.

**Pass if:** stack is visible on Missions without opening Settings; pulse still present underneath.

### C. Detail + Discuss → Chat with context

1. On a mission row, tap **Open** → detail shows phase, situation/why/purpose, Must / Should / Nice targets.
2. Tap **Discuss** (mission or target) → switches to **Chat** with a Mission discuss banner.
3. Send a short message; framing should include mission context (and focus target when Discuss was on a target).

**Pass if:** Discuss lands in Chat with Mission framing, not a blank generic chat.

### D. Make Primary / Promote Dream

1. If a Supporting mission exists: tap **Make Primary** → it becomes Primary after refresh.
2. If a Dream exists: tap **Promote** → it promotes (stack refresh).

**Pass if:** bridge actions succeed and Missions UI updates.

### E. Settings Edit / Discovery still work

1. Settings → You & Oversight → **Life Mission · Edit** still opens the editor.
2. **Mission Discovery · Begin** still runs the ceremony.
3. **Mission Stack · Open tab** switches to the Missions tab (no text-dump dialog).

**Pass if:** Edit + Discovery unchanged; Open tab jumps to Missions.

---

## Pass criteria (summary)

- [ ] Tabs are Chat · Missions · Settings  
- [ ] Mission Stack visible on Missions without Settings burial  
- [ ] Discuss opens Chat with mission/target context  
- [ ] Make Primary works (when supporting exists)  
- [ ] Settings Discovery + Edit still work  
- [ ] Pulse still visible under Missions  
- [ ] About / build stamp shows **5.2.69**
