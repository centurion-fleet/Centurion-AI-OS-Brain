# QA Report for Titus — Attention badges + Discuss sessions (Brain v5.2.70)

**Date:** 2026-07-29  
**Brain tag:** `v5.2.69` → **`v5.2.70`** (this cut)  
**Remote App Store:** no bump  

---

## What this cut is for

| Area | Before | After |
|------|--------|--------|
| Tab badges | Whole title changed (`Settings (!)`, `Missions (3)`) | Title stays normal; only `(!)` / `(N)` is **red** |
| Settings clarity | `!` with no explanation inside the tab | Banner lists why (thinking / remotes offline) + red marks on those rows |
| Missions clarity | Count only on the tab | Banner lists which pills have new items |
| Chat badge | None | Red `(!)` when a tool approval is pending |
| Discuss from Missions | Continued whatever unrelated chat was open | Opens/resumes a chat **named for the topic** (mission title, etc.) |

---

## Install — Brain (Titus / Linux host)

```bash
cd ~/Centurion-AI-OS
git fetch --tags origin
git checkout v5.2.70
desktop-native/scripts/install-user.sh
```

Or Settings → Check for update → Update now (from 5.2.69).

Quit/reopen — About should show **5.2.70**.

**Rollback:** `git checkout v5.2.69` + re-run `install-user.sh`.

---

## QA checklist

### A. Red tab marks only

1. Force Settings attention (unhealthy thinking or all remotes offline).
2. Tab should read **Settings** in normal color with red `(!)`.
3. Missions with unread pills: **Missions** + red `(N)`.

**Pass if:** only the mark is red; the word Chat/Missions/Settings is not.

### B. Settings explains the `!`

1. Open Settings.
2. Expect a top banner: **Needs your attention** with bullets (thinking and/or remotes).
3. Thinking row and/or Connected Devices show a red `(!)`.

**Pass if:** you can tell what the tab `!` referred to without guessing.

### C. Missions explains the `(N)`

1. Open Missions when the badge shows a count.
2. Expect a banner listing pills with new items (e.g. Plans, Needs your choice).

**Pass if:** the count maps to named pulse categories.

### D. Discuss opens a topic-named chat

1. On Missions → Primary Mission, tap the discuss (envelope) control.
2. Chat tab opens with header = mission name (not an old unrelated thread).
3. Conversations sidebar shows that named chat (immediately, or after first send).
4. Discuss the same mission again → resumes that thread (does not append into a random other chat).
5. Repeat for a Supporting mission / target Discuss if available.

**Pass if:** Discuss never continues an unrelated conversation.

### E. Chat approval badge

1. Trigger a tool approval in Chat.
2. Expect Chat tab red `(!)` and the approval strip with a red mark.
3. Resolve approval → badge clears.

---

## Pass criteria (summary)

- [ ] Tab marks are red; titles stay normal  
- [ ] Settings banner explains `!`  
- [ ] Missions banner explains `(N)`  
- [ ] Discuss opens/resumes a topic-named chat  
- [ ] About / build stamp shows **5.2.70**
