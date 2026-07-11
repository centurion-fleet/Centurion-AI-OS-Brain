# Centurion Desktop Native Architecture

## Decision

Centurion Desktop v1 is a native Fedora application built with Rust, GTK4, and
libadwaita. The existing Tauri scaffold remains a reference prototype but is
not the shipping shell.

This choice gives Centurion first-class GNOME integration, one Rust codebase
for the native UI and secure remote service, RPM-friendly packaging, and no
browser runtime in the product interface.

## Product boundary

The Linux machine is the Personal Centurion:

- The existing Python core owns agents, tools, models, memory, sessions, cron,
  and gateways.
- `centurion-remote` owns LAN discovery, encrypted iPhone sessions, and the
  bridge into the Python core.
- `centurion-desktop` owns the native window, device status, service
  supervision, and operator controls.
- CenturionAI Remote on iPhone is a conduit. It does not run the agent.

## Process model

```text
centurion-desktop (Rust + GTK4/libadwaita)
  ├── supervises centurion-remote
  ├── reads service/device status
  └── launches local Centurion surfaces

centurion-remote (Rust + Tokio)
  ├── advertises _centurion._tcp on port 9119
  ├── accepts encrypted iPhone TCP sessions
  ├── tracks connected devices
  └── invokes the Python bridge for agent turns

Centurion AI OS (Python)
  └── existing AIAgent/session/runtime services
```

Processes communicate over local-only IPC. The remote listener never exposes
dashboard configuration, environment variables, or administrative APIs to the
LAN.

## Protocol authority

The shipping protocol matches the existing iOS implementation:

1. iOS discovers `_centurion._tcp` through Bonjour.
2. iOS opens TCP to the resolved service endpoint.
3. Client sends `0x01 || client_public_key[32]`.
4. Server returns `0x01 || server_public_key[32]`.
5. Both derive directional X25519 session keys with libsodium `crypto_kx`.
6. Application frames use a four-byte big-endian payload length followed by
   `nonce[24] || XSalsa20-Poly1305 ciphertext`.

The length prefix is required because TCP is a byte stream; relying on one
write equalling one read is incorrect. iOS and Linux must both implement it.

Protocol messages inside the encrypted payload are UTF-8 JSON:

```json
{"type":"chat","id":"uuid","text":"Hello"}
```

Responses preserve `id`:

```json
{"type":"chat_response","id":"uuid","text":"Hello. How can I help?"}
```

Heartbeat frames use `{"type":"ping"}` and `{"type":"pong"}`. Unknown message
types receive a structured error and do not terminate the session.

## Security model

Version 1 is LAN-only but not unauthenticated:

- Every installation has a persistent server identity key.
- Every iPhone has a persistent Keychain identity key.
- First contact enters `pending approval`; the native desktop shows the device
  name and key fingerprint.
- Approval writes a device record under `CENTURION_HOME`, including public key,
  display name, created time, and last-seen time.
- Revocation immediately terminates active sessions and blocks reconnection.
- Each connection derives independent directional session keys from the pinned
  installation and iPhone identities.
- The listener binds only configured private interfaces and the Fedora
  firewall service opens TCP 9119 only in the trusted zone.

The first implementation may support explicit development auto-approval behind
a flag. Production packaging must default to approval required.

## Native UI v1

The first window intentionally stays small:

- Home: brain readiness, network name, connection status, and one recovery
  action when unhealthy.
- Devices: approved and currently connected iPhones, last seen, revoke.
- Chat: a local conversation using the same Python core.
- Settings: provider readiness, logs, version, and service controls.

GTK surfaces use libadwaita navigation and preferences components. Technical
terms stay behind details. Default copy says “Your Centurion is ready,” not
“mDNS listener active.”

## Packaging

Fedora provisioning ships:

- `centurion-desktop` RPM
- `centurion-remote` binary
- desktop file and hicolor icons
- systemd user service
- firewalld service definition
- provisioning command that installs/configures the Python core

All three products use the same Centurion version. Release checks must compare
the Python package, iOS bundle, and native desktop crate/package metadata.

## Migration from Tauri

The existing `desktop/src-tauri` code is not deleted during v1 development. It
is marked legacy after the native shell can launch, supervise the remote
service, and show device state. Useful tray behavior and naming are carried
forward; the WebView/dashboard embedding is not.

## Verification gates

1. Pure Rust protocol tests cover fragmented/coalesced TCP frames and crypto
   round trips (`cargo test -p centurion-remote`).
2. Python bridge tests use the repository test wrapper and no live model
   (`scripts/run_tests.sh tests/centurion_cli/test_remote_bridge.py`).
3. iOS builds cleanly with Swift-Sodium key exchange and framed TCP chat.
4. Fedora CI builds the native workspace in a clean container (GTK4 +
   libadwaita + VTE).
5. Loopback smoke: `desktop-native/scripts/e2e-smoke.sh`.
6. Physical iPhone E2E on dedicated Fedora hardware: discovery → approval →
   encrypted chat → reconnect with pinned server key → revoke → re-approval.
