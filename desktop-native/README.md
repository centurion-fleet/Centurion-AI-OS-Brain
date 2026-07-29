# Sovereign AI Brain (Linux)

Native GTK4/libadwaita desktop application and encrypted iPhone service for
Fedora-based Personal Centurion hardware.

## Product focus (Brain first)

The **desktop Brain is the product**: Chat, **Missions** (React Mission Deck
embedded via WebKit — `web-dashboard/`), Settings (Soul, memory, thinking, fleet).
Treat the iPhone remote as an optional thin client — do **not** expand pairing,
relay, stream, or Unbox-as-product work unless fixing a security or build blocker.
Revisit ambient phone when the Brain experience is solid and the connection layer
is invisible.

Chrome is **Amber Horizon** (warm charcoal + amber) across Chat, Missions, and
Settings so the whole window feels like one product.

See also: [Client plugins](../website/docs/developer-guide/client-plugins.md)
(agent vs dashboard vs Brain plugin surfaces).

**Away-from-home pairing** remains available for existing remotes but is not the
primary first-run story. First launch teaches what a Centurion *is*; pairing QR
is opt-in from Settings → Status.

## Components

- `centurion-desktop`: native Linux window (**Sovereign AI Brain**) and pairing controls
- `centurion-remote`: mDNS discovery, encrypted TCP sessions, and Python bridge
- `centurion-common`: versioned wire messages and framing

The Tauri prototype under `desktop/` is not used by this application.

## User-local install (Track B, no RPM)

After Fedora build dependencies are installed:

```bash
chmod +x desktop-native/scripts/install-user.sh
desktop-native/scripts/install-user.sh
```

This builds `centurion-remote` and `centurion-desktop`, installs both to
`~/.local/bin`, replaces any stale Tauri `centurion-desktop.desktop` launcher,
installs icons, and enables the user `centurion-remote` systemd unit.

The application menu name is **Sovereign AI Brain**. Settings → **Check for updates**
runs `centurion update --check --json` and can apply Centurion AI OS updates
(`centurion update -y`). That path updates the Python brain, not the GTK binary —
rebuild the desktop app with `install-user.sh` (or the Fedora RPM) when you need
a new shell build.

If an old menu entry pointed at `desktop/launch.sh`, remove it or let the
installer replace it.

## Fedora development

```bash
sudo dnf install \
  cargo rust gcc gcc-c++ pkgconf-pkg-config \
  gtk4-devel libadwaita-devel webkitgtk6.0-devel vte291-gtk4-devel \
  nodejs npm

cargo build --workspace
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings -A deprecated
```

Run the service in explicit development pairing mode:

```bash
cargo run -p centurion-remote -- serve --auto-approve --echo
```

Production mode requires approval (LAN) or a remote pairing token:

```bash
cargo run -p centurion-remote -- serve
cargo run -p centurion-remote -- remote-pair --host your.public.hostname
# → ASCII QR (TTY) + token:…@your.public.hostname:9119 for the iPhone

cargo run -p centurion-remote -- devices
cargo run -p centurion-remote -- approve <fingerprint> --name "Adrian's iPhone"
```

Or via the Python CLI wrapper (same binary under the hood):

```bash
centurion remote pair --host your.public.hostname
# Flags: --qr / --no-qr, --qr-png PATH, --json --include-qr
centurion remote tokens
centurion remote revoke <id>
```

### Exposing TCP 9119 for away access

See **[docs/EXPOSE_9119.md](docs/EXPOSE_9119.md)** for Cloudflare Tunnel / proxy /
port-forward steps and the advertise-host checklist.

Remote pairing works over any reachable TCP path. Common options:

1. **Cloudflare Tunnel** — `cloudflared tunnel` TCP to `localhost:9119`, use the tunnel hostname in `--host`.
2. **Reverse proxy** — TCP pass-through (nginx stream / Caddy) to `127.0.0.1:9119`.
3. **Firewall / port-forward** — allow inbound TCP 9119 to the brain and use your public IP or DNS name.

Crypto Chat stays end-to-end encrypted (X25519 + XSalsa20-Poly1305) between iPhone and this Centurion. Opening the port only makes the encrypted listener reachable; pair tokens gate new devices.

The native desktop **Link iPhone — show QR** panel mints the same connection string as a full-screen QR (auto-refreshes every few minutes).

## Local chat

The Chat tab embeds the real `centurion --tui` inside a VTE terminal — the same
surface the dashboard PTY uses. No second chat UI is built in GTK widgets.

Requirements on the host:

- `centurion` on `PATH` (Python core installed and configured)
- Node/npm available if the TUI bundle must be built on first launch
- `vte291-gtk4` runtime library (pulled in by the RPM)

## Loopback verification

```bash
chmod +x desktop-native/scripts/e2e-smoke.sh
desktop-native/scripts/e2e-smoke.sh
```

## Physical iPhone E2E (Fedora hardware)

Build the RPM from `packaging/fedora/centurion-desktop.spec`, publish it to the
Centurion provisioning repository, then run:

```bash
desktop-native/packaging/fedora/provision-centurion.sh
```

The installer enables the user service and opens mDNS plus TCP 9119 in
firewalld's trusted zone. Provisioning must assign only the Centurion LAN
interface to that zone.

### Same-day smoke checklist (Ships_AI Fedora + TestFlight iPhone)

1. On Fedora: `git pull` on this tree, then
   `desktop-native/scripts/install-user.sh` (or `provision-centurion.sh`).
2. Confirm `systemctl --user status centurion-remote` is active; expose TCP 9119
   (see `docs/EXPOSE_9119.md`) with a public/tunnel hostname.
3. On iPhone (TestFlight, **cellular**): Connect → **Scan QR** on Brain screen
   (or terminal QR from `centurion remote pair --host …`) → approve if prompted.
4. Crypto Chat: send one message and confirm a real model reply.
5. Settings → Check for updates: confirm status dialog; Update now when behind.
6. Pulse: confirm live feed updates (not sample/static activity).
7. Swarm: connect and confirm status reflects the host session.
8. Get Help: generate a support code on phone; look it up under GTK
   Settings → Support Tools.
9. Early Centurions only: GTK Settings → Transition → Bring over Telegram
   history (not on iPhone).

## Security notes

- Approved device and server identity data are profile-scoped under
  `CENTURION_HOME/remote/`.
- The server identity file is created with mode `0600`.
- iOS stores its identity and the pinned server public key in Keychain.
- The LAN listener exposes only the remote protocol, never dashboard/admin
  endpoints.
- `--auto-approve` and `--echo` are development flags and are absent from the
  systemd service.
