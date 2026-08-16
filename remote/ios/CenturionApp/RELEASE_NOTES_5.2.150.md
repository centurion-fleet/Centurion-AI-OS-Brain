# Centurion v5.2.150 — Brain + Sovereign AI Remote

## Why this build

After pairing, Crypto Chat and Focus were racing on the same local socket, so a same-room `Hi` could hang or desync before missions were on the phone. This release loads mission data first, then unlocks Chat.

## Brain (Linux)

- Same warm daemon as **5.2.149** (`$CENTURION_HOME/run/bridge.sock`). No Cloudflare tunnel required for home Wi‑Fi.
- Get Brain: keep `centurion-brain-5.2.149` if already installed, or publish `centurion-brain-5.2.150` for lockstep.

## Remote (iPhone)

- After pairing, Chat shows **Loading mission data. Please wait.** and keeps the composer locked until missions/plans are on the phone.
- Then send one `Hi` on Chat. Do not treat a green lock as “Chat is ready” until that wait ends.
- TestFlight marketing **5.2.150** / build **42**.

## Away / App Store wording

Chat from anywhere remains **ops-gated**. Same-room LAN first; Cloudflare / tunnel work is later.
