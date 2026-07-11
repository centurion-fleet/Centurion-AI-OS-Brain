#!/usr/bin/env bash
set -euo pipefail

# Loopback smoke test for the encrypted iPhone protocol path.
# Run from the repository root after `cargo build --release` in desktop-native/.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY="${ROOT}/desktop-native/target/release/centurion-remote"
PORT="${CENTURION_REMOTE_PORT:-19119}"
BIND="127.0.0.1:${PORT}"
CENTURION_HOME="${CENTURION_HOME:-$(mktemp -d)}"
export CENTURION_HOME

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -x "${BINARY}" ]]; then
  echo "Building centurion-remote…" >&2
  cargo build --release --manifest-path "${ROOT}/desktop-native/Cargo.toml" -p centurion-remote
fi

echo "CENTURION_HOME=${CENTURION_HOME}"
"${BINARY}" serve --bind "${BIND}" --auto-approve --echo &
SERVER_PID=$!
sleep 1

export CENTURION_REMOTE_SMOKE_BIND="${BIND}"
cargo test --manifest-path "${ROOT}/desktop-native/Cargo.toml" -p centurion-remote --test loopback smoke_bind_echo_round_trip -- --nocapture
cargo test --manifest-path "${ROOT}/desktop-native/Cargo.toml" -p centurion-remote --test loopback -- --nocapture

echo
echo "Loopback smoke test passed."
echo
echo "Physical iPhone E2E checklist (Fedora hardware):"
echo "  1. Run desktop-native/packaging/fedora/provision-centurion.sh"
echo "  2. Confirm: systemctl --user status centurion-remote"
echo "  3. Confirm: firewall-cmd --zone=trusted --list-services | grep centurion-remote"
echo "  4. Open Centurion desktop → Devices → approve pending fingerprint"
echo "  5. On iPhone: Connect tab → discover → connect → send chat"
echo "  6. Revoke device on desktop → reconnect should require re-approval"
echo "  7. Restart centurion-remote → iPhone should reconnect with pinned server key"
