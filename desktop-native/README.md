# Centurion Desktop for Linux

Native GTK4/libadwaita desktop application and encrypted iPhone service for
Fedora-based Personal Centurion hardware.

## Components

- `centurion-desktop`: native Linux window and pairing controls
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

If an old menu entry pointed at `desktop/launch.sh`, remove it or let the
installer replace it.

## Fedora development

```bash
sudo dnf install \
  cargo rust gcc gcc-c++ pkgconf-pkg-config \
  gtk4-devel libadwaita-devel vte291-gtk4-devel

cargo build --workspace
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Run the service in explicit development pairing mode:

```bash
cargo run -p centurion-remote -- serve --auto-approve --echo
```

Production mode requires approval:

```bash
cargo run -p centurion-remote -- serve
cargo run -p centurion-remote -- devices
cargo run -p centurion-remote -- approve <fingerprint> --name "Adrian's iPhone"
```

The native desktop performs the same approval action from its Devices page.

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

### Tomorrow smoke checklist (Ships_AI Fedora + TestFlight iPhone)

1. On Fedora: `git pull` on this tree, then
   `desktop-native/scripts/install-user.sh` (or `provision-centurion.sh`).
2. Confirm `systemctl --user status centurion-remote` is active and Bonjour
   advertises the host.
3. On iPhone (TestFlight build): same Wi‑Fi, Connect → pair → approve on GTK
   Devices.
4. Crypto Chat: send one message and confirm a real model reply.
5. Pulse: confirm live feed updates (not sample/static activity).
6. Swarm: connect and confirm status reflects the host session.
7. Get Help: generate a support code on phone; look it up under GTK
   Settings → Support Tools.
8. Early Centurions only: GTK Settings → Transition → Bring over Telegram
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
