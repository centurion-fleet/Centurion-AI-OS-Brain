# Customer cutover — Brain + Remote (3-hour window)

**Brain tag:** `v5.2.57`  
**Remote:** Sovereign AI Remote **5.1.0** (build **29**)  
**Do not ship:** dirty license/fleet/billing WIP; pairing/Unbox redesign; iOS bump to 5.2.x

---

## What customers get

| Surface | Ready |
|---------|--------|
| Home chat-bubble discuss icons on cards / commitments / orbs | Yes |
| Pill numeric capsule badges (counts before first visit) | Yes |
| Live pill presence `0/1` | Yes |
| Home tab `Home (N)` attention badge | Yes |
| Settings tab `Settings (!)` for thinking / offline remotes | Yes |
| Chat tab unbadged (Remote parity) | Yes |
| Prior Chat Activity + stick-to-bottom | Yes (5.2.55–56) |

---

## Host install (each Linux Brain)

```bash
cd ~/Centurion-AI-OS
git fetch --tags origin
git checkout v5.2.57
desktop-native/scripts/install-user.sh
```

Then:

1. Quit and reopen **Sovereign AI Brain** — About shows **5.2.57**.
2. Home: pills show numeric capsules before first visit; open a pill → that badge clears; Live stays `1` while work is active.
3. Home tab title shows `Home (N)` matching unread pill totals; Chat stays plain `Chat`.
4. Card / commitment / orb rows show a chat icon; click seeds Chat discuss.
5. Degrade thinking (or approved remotes all offline) → Settings shows `Settings (!)`.

**Rollback:** `git checkout v5.2.56` + re-run `install-user.sh`.

---

## Product note (v5.2.57)

Closes the visible Home/tab chrome gaps vs iPhone Remote: discuss icons, real pill new-counts (removed the first-visit gate), Live presence badge, and StackSwitcher attention titles. Chat remains unbadged.

### Settings vs You (no rewrite this cut)

Brain Settings stays a **host hub** (Fleet, plugins, ops, gateway, license, pairing, thinking) and already covers the Remote You destinations that matter for desk use (Mission, Soul, Autonomy, Memory Horizon, Oversight, Privacy, Support/Adrian). Remote-only extras (Appearance theme picker, Reset Identity, sales showcase) stay out of this ship.
