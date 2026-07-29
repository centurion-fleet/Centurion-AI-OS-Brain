# QA Report for Titus — Missions gaps #2 + #3 (Brain v5.2.59)

**Date:** 2026-07-29  
**Brain tag:** `v5.2.58` → **`v5.2.59`** (this cut)  
**Remote App Store:** still **5.1.0 (29)** — no store bump; iOS inject QA is **Xcode / TestFlight from `main`**, not App Store  
**Owner ask:** Fix Decision Log writers (#2) + iOS context inject (#3); Activity Hub firehose stays Day 2  

---

## What this cut is for

Honest gap check said:

| Gap | Before | After this cut |
|-----|--------|----------------|
| **#3 iOS context inject** | Helper existed; send path did not call it; Discuss was a stub | Wired on chat send for Mission / Target / Commitment; Discuss opens real Chat |
| **#2 Decision Log writers** | Table + tool existed; nothing auto-wrote on approve | Brain `plan_decide` + `swarm_resolve_signal` write `life_decisions` |
| **#1 Activity Hub firehose** | Home pills = Swarm data; Chat is default tab | **Not in this cut** (Day 2) |

---

## Install — Brain (Titus / Linux host)

```bash
cd ~/Centurion-AI-OS
git fetch --tags origin
git checkout v5.2.59
desktop-native/scripts/install-user.sh
```

Quit and reopen **Sovereign AI Brain** — About should show **5.2.59**.

**Rollback:** `git checkout v5.2.58` + re-run `install-user.sh`.

---

## Install — Remote (iPhone inject QA only)

App Store build **does not** include inject yet. For QA:

1. Build **Sovereign AI Remote** from this repo’s `ios/CenturionApp` on `main` / `v5.2.59` (Marketing version can stay 5.1.0).
2. Link to the Brain on `v5.2.59` over Crypto Chat as usual.
3. Confirm Brain About is **5.2.59** before testing inject (Brain must serve `life_call` / `life_context_inject`).

---

## Automated checks (already green locally)

```bash
scripts/run_tests.sh tests/centurion_cli/test_life_missions.py
```

Expect **6 passed**, including `test_plan_decide_writes_life_decision`.

---

## QA checklist — Decision Log (#2) — Brain + either client

### A. Plan approve writes a decision

1. On Brain (or Remote linked to Brain), ensure a Life Mission exists (Mission Discovery / Edit / Mission Stack).
2. Create or open a plan that needs a choice (Home → Plans / Needs your choice).
3. **Approve** the plan (with a note if the UI allows — e.g. “Go with the amber colour direction”).
4. Verify Decision Log has a row:

```bash
# On the Brain host
python - <<'PY'
from centurion_cli.life_missions import list_decisions
for d in list_decisions(limit=5):
    print(d.get("chosen"), "|", d.get("human_said"), "|", d.get("title"))
PY
```

**Pass if:** newest row shows chosen like `Approved — proceed`, and the note appears in `human_said` when provided.

### B. Context inject can cite last decision

1. After A, open Life Mission discuss on **Brain** Chat (Home / Settings → discuss Life Mission).
2. Send: `What was my last decision on the plan?`
3. Or bridge smoke:

```bash
echo '{"id":"t","action":"life_context_inject","message":"what next?"}' | python -m centurion_cli.remote_bridge
```

**Pass if:** `formatted_for_ai` (or the discuss framing) includes a **Last decision:** line with the approval text.

### C. Collaboration resolve (optional)

1. Resolve a swarm “Needs your choice” signal from Remote or Brain.
2. Re-run `list_decisions` — expect a Collaboration choice row with `chosen=resolved`.

**Pass if:** row appears; primary resolve flow still succeeds (logging must not break approve/resolve).

---

## QA checklist — iOS context inject (#3)

**Requires Remote built from this cut + Brain v5.2.59.**

### D. Mission Discuss attaches context

1. Home → Mission Stack (banner) → open **Primary** (or a supporting Mission).
2. Tap **Discuss** → real Chat sheet (not a plain “Discuss · …” label).
3. Send: `change the colour` (or any short ambiguous ask).
4. On Brain, confirm the outbound user turn was framed with Mission context (agent.log / discuss framing), **or** observe the model answers about **that** Mission without asking “which project?”.

**Pass if:** Chat opens for real, and the Brain receives Mission context (Subject / Mission / phase / focus), not a bare “change the colour”.

### E. Target row Discuss

1. Mission detail → tap a **Must Do / Should Do / Nice to Do** row (chat bubble).
2. Send a short message about that target.

**Pass if:** context includes that **Target** sequence/title (Focus Target if applicable).

### F. Soft-fail offline

1. Disconnect Remote from Brain.
2. Open a mission chat and send a message (expect not connected / existing error).
3. Reconnect — inject works again without crashing.

**Pass if:** no crash when inject cannot run; connected path still injects.

### G. Regression — plan / propose-first chat

1. Open Plan Discuss from Home; send a normal message.
2. Spot-check Propose First if you use it.

**Pass if:** plan framing still works; Mission inject did not break plan/commitment paths.

---

## Explicitly out of scope this cut (do not fail QA)

- Activity Hub as default tab / single Life Missions firehose of wins+outputs+thoughts+decisions  
- App Store Remote 5.1.0 rebuild / version lockstep bump  
- Portal / Supabase Mission Control  

---

## Suggested Titus verdict lines

Copy into your note:

```
Brain v5.2.59 QA
[ ] A Plan approve → life_decisions row
[ ] B Inject / discuss cites Last decision
[ ] C Swarm resolve → decision row (optional)
[ ] D iOS Mission Discuss + inject (Xcode build)
[ ] E iOS Target Discuss + inject
[ ] F Inject soft-fail when offline
[ ] G Plan discuss regression

Verdict: PASS / FAIL
Notes:
```

---

## Files in this cut (for audit)

| Area | Files |
|------|--------|
| Decision writers | `centurion_cli/remote_bridge.py` (`_record_life_decision` on `plan_decide` / `swarm_resolve_signal`) |
| Tests | `tests/centurion_cli/test_life_missions.py` |
| iOS inject + Discuss | `MessageService.swift`, `Conversation.swift`, `MissionStackView.swift` (+ Mission models/store/portfolio wiring on `main`) |
| Version | `5.2.59` — `centurion_cli/__init__.py`, `pyproject.toml`, `desktop-native/Cargo.toml` |
