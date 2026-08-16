# Centurion v5.2.149 — Brain + Sovereign AI Remote

## Why this build

Phone Crypto Chat was cold-starting a new Centurion on every `Hi` while desk Chat reused the warm daemon. This release routes iPhone Chat through that same daemon so a linked Remote gets a spoken reply instead of hanging on “Waiting on your Sovereign”.

## Brain (Linux)

- `centurion-remote` reuses `$CENTURION_HOME/run/bridge.sock` (starts the daemon at boot if GTK has not).
- Activity is sent as soon as a Chat frame arrives.
- Get Brain: publish `centurion-brain-5.2.149` (full Fedora RPM).

## Remote (iPhone)

- Stay on Chat during a turn (Focus does not steal the line).
- Stop + honest errors if the Sovereign is slow or the socket drops.
- TestFlight marketing **5.2.149** / build **41**.

## Away / App Store wording

Chat from anywhere remains **ops-gated**. App Store does **not** yet claim finished “works anywhere” until Away DoD in `brain/linux/docs/REMOTE_RELAY.md` is green on cellular + CGNAT.
