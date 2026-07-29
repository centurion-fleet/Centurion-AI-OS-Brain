# Customer cutover — Brain + Remote (3-hour window)

**Brain tag:** `v5.2.58`  
**Remote:** Sovereign AI Remote **5.1.0** (build **29**) — no App Store bump this cut  
**Do not ship:** dirty license/fleet/billing WIP; pairing/Unbox redesign; portal/Supabase Missions

---

## What customers get

| Surface | Ready |
|---------|--------|
| Offline Life Missions store (`~/.centurion/life/life.db`) | Yes |
| Subjects → Missions → Targets (Must / Should / Nice) | Yes |
| Mission Stack (primary / supporting / dreams) via bridge | Yes |
| Settings → **Mission Stack** panel | Yes |
| Chat Life Mission discuss injects Brain context (user message only) | Yes |
| Agent tools: `life_missions`, `subject_resolver`, `thought_stream` | Yes |
| Legacy `mission_get` / `mission_put` (Remote + Edit) still work | Yes |
| Prior Home chrome / Chat Activity / stick-to-bottom | Yes (5.2.55–57) |

---

## Host install (each Linux Brain)

```bash
cd ~/Centurion-AI-OS
git fetch --tags origin
git checkout v5.2.58
desktop-native/scripts/install-user.sh
```

Then:

1. Quit and reopen **Sovereign AI Brain** — About shows **5.2.58**.
2. Settings → You & Oversight → **Mission Stack** → Open — see primary / supporting / dreams / subjects.
3. Settings → Life Mission → Edit (or Mission Discovery) still works; saves land in `life.db` and regenerate `LIFE_MISSION.md`.
4. Home → discuss Life Mission → Chat framing includes injected mission context when the bridge is up.
5. Optional smoke: `python -m centurion_cli.remote_bridge` with `{"id":"t","action":"life_stack_get"}` on stdin.

**Rollback:** `git checkout v5.2.57` + re-run `install-user.sh`.

---

## Product note (v5.2.58)

Missions Full System **offline on the Brain** — no Supabase / portal Mission Control. Source of truth is `{CENTURION_HOME}/life/life.db`. iPhone Remote can use Crypto Chat `life_call` once a Remote build that includes it ships; this cut is Brain-first so you can play on the desk today.
