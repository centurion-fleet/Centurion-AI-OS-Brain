# Centurion Mission Deck

Offline-first hero UI for Life Missions on the Brain.

**In the Sovereign AI Brain app**, the Missions tab embeds this UI via WebKitGTK
(supervised `node server.js` on `127.0.0.1:9120`). Standalone use is still supported.

## Run

```bash
cd web-dashboard
npm install
npm run dev      # Vite :5173 + API :9120
npm run build
npm start        # serves dist/ on :9120
```

Data: local `{CENTURION_HOME}/life/life.db` via `python -m centurion_cli.remote_bridge`.
No Supabase, no cloud DB, no auth (LAN Brain only).

Brain install (`desktop-native/scripts/install-user.sh`) builds this package into
`~/.local/share/centurion/mission-deck` and sets `CENTURION_MISSION_DECK_DIR`.
