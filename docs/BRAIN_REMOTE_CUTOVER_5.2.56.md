# Customer cutover — Brain + Remote (3-hour window)

**Brain tag:** `v5.2.56`  
**Remote:** Sovereign AI Remote **5.1.0** (build **29**)  
**Do not ship:** dirty license/fleet/billing WIP; pairing/Unbox redesign; iOS bump to 5.2.x

---

## What customers get

| Surface | Ready |
|---------|--------|
| Brain Chat Cursor-style stick-to-bottom scroll | Yes |
| Live Activity feed inside transcript (tools + thinking) | Yes |
| Home pulse / Settings desk chrome | Yes |
| Same-Wi‑Fi QR pair → phone Crypto Chat | Yes (smoke required) |

---

## Host install (each Linux Brain)

```bash
cd ~/Centurion-AI-OS
git fetch --tags origin
git checkout v5.2.56
desktop-native/scripts/install-user.sh
```

Then:

1. Quit and reopen **Sovereign AI Brain** — About shows **5.2.56**.
2. Chat: send a tool-heavy prompt. Confirm the transcript **auto-scrolls** so Working/Thinking/tools stay visible without manual scroll.
3. Scroll up mid-turn — follow pauses; scroll back to bottom or send again — follow resumes.
4. Confirm the latest content is not clipped under the composer (spacer breathing room).

**Rollback:** `git checkout v5.2.55` + re-run `install-user.sh`.

---

## Product note (v5.2.56)

Activity card moved inside the Chat ScrolledWindow with the message list. Stick-to-bottom hardened (idle clear of programmatic flag, size-allocate re-pin, 80px near-bottom threshold) so Brain Chat matches Cursor’s “never chase the fold” feel.
