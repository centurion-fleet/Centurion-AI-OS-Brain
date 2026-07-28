# Customer cutover — Brain + Remote (3-hour window)

**Brain tag:** `v5.2.55`  
**Remote:** Sovereign AI Remote **5.1.0** (build **29**)  
**Do not ship:** dirty license/fleet/billing WIP; pairing/Unbox redesign; iOS bump to 5.2.x

---

## What customers get

| Surface | Ready |
|---------|--------|
| Brain Chat live Activity feed (tools + thinking + status) | Yes |
| Brain Home pulse / Settings desk chrome (5.2.54) | Yes |
| Plan / Decision / Commitment / Horizon discuss | Yes |
| Same-Wi‑Fi QR pair → phone Crypto Chat | Yes (smoke required) |
| Away-from-home / Unbox product work | Frozen — existing path only |

---

## Host install (each Linux Brain)

```bash
cd ~/Centurion-AI-OS   # or customer checkout path
git fetch --tags origin
git checkout v5.2.55
desktop-native/scripts/install-user.sh
```

Then:

1. Quit and reopen **Sovereign AI Brain**.
2. Confirm About shows **5.2.55**.
3. Chat: ask something that uses tools (e.g. read a file / search). Confirm the **Working…** activity card shows tool lines (and thinking when available) before the final reply.
4. Confirm a collapsed “Worked with …” summary appears above the assistant bubble.
5. Confirm approvals still work for dangerous tools.
6. Optional: `display.tool_progress: off` (or `display.platforms.remote.tool_progress: off`) keeps spinner-only.

**Rollback:** `git checkout v5.2.54` + re-run `install-user.sh`.

---

## Product note (v5.2.55)

Brain Chat mirrors Cursor/Telegram mid-turn transparency via `remote_bridge` NDJSON `centurion_event=activity` (tools, thinking, status). Final reply remains one bubble; token streaming deferred.
