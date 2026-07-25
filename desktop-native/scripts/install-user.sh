#!/usr/bin/env bash
set -euo pipefail

# User-local install for Track B (no RPM/sudo after build deps are present).
# Installs centurion-remote + centurion-desktop, icons, and a working .desktop entry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_NATIVE="${ROOT}/desktop-native"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

echo "Building native binaries…"
cargo build --release \
  --manifest-path "${DESKTOP_NATIVE}/Cargo.toml" \
  -p centurion-remote \
  -p centurion-desktop

mkdir -p "${BIN_DIR}"
install -m 0755 "${DESKTOP_NATIVE}/target/release/centurion-remote" "${BIN_DIR}/"
install -m 0755 "${DESKTOP_NATIVE}/target/release/centurion-desktop" "${BIN_DIR}/"

echo "Installing menu entry and icons…"
mkdir -p "${APP_DIR}" "${ICON_DIR}"
# Remove stale Tauri launcher if present.
rm -f "${APP_DIR}/centurion-desktop.desktop"
sed "s|^Exec=centurion-desktop$|Exec=${BIN_DIR}/centurion-desktop|" \
  "${DESKTOP_NATIVE}/resources/com.centurion.desktop.desktop" \
  > "${APP_DIR}/com.centurion.desktop.desktop"
chmod 0644 "${APP_DIR}/com.centurion.desktop.desktop"
for size in 16 22 24 32 48 64 128 256 512; do
  install -D -m 0644 \
    "${DESKTOP_NATIVE}/resources/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png" \
    "${ICON_DIR}/${size}x${size}/apps/com.centurion.desktop.png"
done
install -D -m 0644 \
  "${DESKTOP_NATIVE}/resources/icons/hicolor/scalable/apps/com.centurion.desktop.png" \
  "${ICON_DIR}/scalable/apps/com.centurion.desktop.png"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${APP_DIR}" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f "${ICON_DIR}" || true
fi

echo "Installing user systemd unit for centurion-remote…"
mkdir -p "${SYSTEMD_DIR}"

# Prefer Centurion venv python so the remote bridge can import centurion_cli.
PYTHON_BIN="python3"
for candidate in \
  "${ROOT}/.venv/bin/python" \
  "${ROOT}/venv/bin/python" \
  "${HOME}/.centurion/Centurion-AI-OS/venv/bin/python" \
  "${HOME}/.centurion/venv/bin/python"
do
  if [[ -x "${candidate}" ]]; then
    PYTHON_BIN="${candidate}"
    break
  fi
done

{
  sed 's|ExecStart=/usr/bin/centurion-remote|ExecStart=%h/.local/bin/centurion-remote|' \
    "${DESKTOP_NATIVE}/packaging/systemd/centurion-remote.service"
  printf 'WorkingDirectory=%s\n' "${ROOT}"
  printf 'Environment=TERMINAL_CWD=%s\n' "${ROOT}"
  printf 'Environment=CENTURION_AI_REPO=%s\n' "${ROOT}"
  printf 'ReadWritePaths=%s\n' "${ROOT}"
  # Away-from-home: advertise a public/tunnel host when set.
  if [[ -n "${CENTURION_REMOTE_ADVERTISE_HOST:-}" ]]; then
    printf 'Environment=CENTURION_REMOTE_ADVERTISE_HOST=%s\n' "${CENTURION_REMOTE_ADVERTISE_HOST}"
  fi
  printf 'ExecStart=\n'
  printf 'ExecStart=%%h/.local/bin/centurion-remote serve --name "Sovereign AI Brain" --python %s\n' "${PYTHON_BIN}"
} > "${SYSTEMD_DIR}/centurion-remote.service"

# Fail fast if the bridge module is missing on the chosen interpreter.
if ! "${PYTHON_BIN}" -c "import centurion_cli.remote_bridge" >/dev/null 2>&1; then
  echo "ERROR: ${PYTHON_BIN} cannot import centurion_cli.remote_bridge." >&2
  echo "Install Centurion AI OS into this interpreter, then re-run install-user.sh." >&2
  exit 1
fi

export PATH="${BIN_DIR}:${PATH}"
systemctl --user daemon-reload
systemctl --user enable --now centurion-remote.service

echo
echo "Away-from-home pairing (required for iPhone Remote):"
echo "  export CENTURION_REMOTE_ADVERTISE_HOST=<public-or-tunnel-hostname>"
echo "  centurion remote pair --host \"\$CENTURION_REMOTE_ADVERTISE_HOST\""
echo "  # Prints a QR (TTY) + token:…@host:9119 — scan in Sovereign AI Remote"
echo "  # Or open Sovereign AI Brain → Link iPhone — show QR"
echo "Expose TCP 9119 via Cloudflare Tunnel / reverse proxy / port-forward."
echo "See desktop-native/docs/EXPOSE_9119.md"
echo
if [[ ! -x "${BIN_DIR}/centurion-desktop" ]]; then
  echo "ERROR: ${BIN_DIR}/centurion-desktop was not built." >&2
  exit 1
fi

echo
echo "Installed:"
echo "  ${BIN_DIR}/centurion-remote"
echo "  ${BIN_DIR}/centurion-desktop"
echo "  ${APP_DIR}/com.centurion.desktop.desktop"
echo "  Python bridge: ${PYTHON_BIN}"
echo
echo "Launch GUI:"
echo "  ${BIN_DIR}/centurion-desktop"
echo
echo "If the app menu still lacks the icon, log out and back in."
