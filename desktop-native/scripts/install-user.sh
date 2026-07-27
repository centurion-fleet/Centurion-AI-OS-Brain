#!/usr/bin/env bash
set -euo pipefail

# Brain Settings updates are often launched from the GUI with a minimal PATH.
if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

# User-local install for Track B (no RPM/sudo after build deps are present).
# Installs centurion-remote + centurion-desktop, icons, and a working .desktop entry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_NATIVE="${ROOT}/desktop-native"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

# Settings → Update can re-apply a dirty autostash after git pull. Reset the
# screen sources to HEAD so this rebuild matches the release that was pulled.
if git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${ROOT}" checkout -- desktop-native >/dev/null 2>&1 || true
  git -C "${ROOT}" clean -fd -- desktop-native >/dev/null 2>&1 || true
fi

echo "Building native binaries…"
BUILD_LOG="${HOME}/.centurion/logs/desktop-build.log"
mkdir -p "$(dirname "${BUILD_LOG}")"
if ! cargo build --release \
  --manifest-path "${DESKTOP_NATIVE}/Cargo.toml" \
  -p centurion-remote \
  -p centurion-desktop >"${BUILD_LOG}" 2>&1
then
  echo "ERROR: cargo build failed. Last lines:" >&2
  tail -n 40 "${BUILD_LOG}" >&2 || true
  echo "Full log: ${BUILD_LOG}" >&2
  exit 1
fi
{
  echo
  echo "Build succeeded at $(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)"
} >>"${BUILD_LOG}"

mkdir -p "${BIN_DIR}"
install -m 0755 "${DESKTOP_NATIVE}/target/release/centurion-remote" "${BIN_DIR}/"
install -m 0755 "${DESKTOP_NATIVE}/target/release/centurion-desktop" "${BIN_DIR}/"

echo "Installing menu entry and icons…"
mkdir -p "${APP_DIR}" "${ICON_DIR}"
# Remove stale Tauri launcher if present.
rm -f "${APP_DIR}/centurion-desktop.desktop"

# Prefer Centurion venv python so the desktop + remote bridges can import centurion_cli.
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

# Pin Centurion Python + repo for Settings (Autonomy/Soul/Horizon) and Chat tab.
# CENTURION_HOME is resolved at runtime (see resolve_centurion_home in the desktop
# app) so a stale active_profile pin cannot hide ~/.centurion/SOUL.md.
resolve_centurion_home_dir() {
  local root="${HOME}/.centurion"
  if [[ -n "${CENTURION_HOME:-}" && -d "${CENTURION_HOME}" ]]; then
    printf '%s\n' "${CENTURION_HOME}"
    return
  fi
  local ap="${root}/active_profile"
  if [[ -f "${ap}" ]]; then
    local name
    name="$(tr -d '[:space:]' < "${ap}" || true)"
    if [[ -n "${name}" && "${name}" != "default" ]]; then
      local profile="${root}/profiles/${name}"
      if [[ -d "${profile}" ]]; then
        printf '%s\n' "${profile}"
        return
      fi
    fi
  fi
  printf '%s\n' "${root}"
}
CENTURION_HOME_DIR="$(resolve_centurion_home_dir)"

cat > "${APP_DIR}/com.centurion.desktop.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sovereign AI Brain
GenericName=Personal AI Brain
Comment=Your private Sovereign AI Brain
Exec=env CENTURION_PYTHON=${PYTHON_BIN} CENTURION_AI_REPO=${ROOT} ${BIN_DIR}/centurion-desktop
Icon=com.centurion.desktop
Terminal=false
Categories=Utility;Network;
Keywords=AI;Assistant;Centurion;Sovereign;Brain;Private;
StartupNotify=true
StartupWMClass=com.centurion.desktop
EOF
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

{
  sed 's|ExecStart=/usr/bin/centurion-remote|ExecStart=%h/.local/bin/centurion-remote|' \
    "${DESKTOP_NATIVE}/packaging/systemd/centurion-remote.service"
  printf 'WorkingDirectory=%s\n' "${ROOT}"
  printf 'Environment=TERMINAL_CWD=%s\n' "${ROOT}"
  printf 'Environment=CENTURION_AI_REPO=%s\n' "${ROOT}"
  printf 'ReadWritePaths=%s\n' "${ROOT}"
  # Away-from-home advertise host: env at install time, or persistent file.
  ADVERTISE_HOST="${CENTURION_REMOTE_ADVERTISE_HOST:-}"
  ADVERTISE_FILE="${HOME}/.centurion/remote/advertise-host"
  if [[ -z "${ADVERTISE_HOST}" && -f "${ADVERTISE_FILE}" ]]; then
    ADVERTISE_HOST="$(tr -d '[:space:]' < "${ADVERTISE_FILE}" || true)"
  fi
  if [[ -n "${ADVERTISE_HOST}" ]]; then
    mkdir -p "${HOME}/.centurion/remote"
    printf '%s\n' "${ADVERTISE_HOST}" > "${ADVERTISE_FILE}"
    chmod 0644 "${ADVERTISE_FILE}" || true
    printf 'Environment=CENTURION_REMOTE_ADVERTISE_HOST=%s\n' "${ADVERTISE_HOST}"
    echo "Persisted advertise host → ${ADVERTISE_FILE}"
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

# Stamp so Settings → Check for update can see when the screen binary is stale.
mkdir -p "${CENTURION_HOME_DIR}"
SCREEN_VERSION="$(
  awk '
    /^\[workspace\.package\]/ { in_pkg=1; next }
    /^\[/ { in_pkg=0 }
    in_pkg && /^version[[:space:]]*=/ {
      gsub(/"/, "", $3); print $3; exit
    }
  ' "${DESKTOP_NATIVE}/Cargo.toml" 2>/dev/null || true
)"
GIT_REV="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
BUILT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)"
cat > "${CENTURION_HOME_DIR}/desktop-build.json" <<EOF
{
  "version": "${SCREEN_VERSION:-unknown}",
  "git_rev": "${GIT_REV}",
  "git_branch": "${GIT_BRANCH}",
  "built_at": "${BUILT_AT}",
  "repo_root": "${ROOT}",
  "binary": "${BIN_DIR}/centurion-desktop"
}
EOF
chmod 0644 "${CENTURION_HOME_DIR}/desktop-build.json" || true

echo
echo "Installed:"
echo "  ${BIN_DIR}/centurion-remote"
echo "  ${BIN_DIR}/centurion-desktop"
echo "  ${APP_DIR}/com.centurion.desktop.desktop"
echo "  Python bridge: ${PYTHON_BIN}"
echo "  Build stamp: ${CENTURION_HOME_DIR}/desktop-build.json (${SCREEN_VERSION:-unknown})"
echo
echo "Launch GUI:"
echo "  ${BIN_DIR}/centurion-desktop"
echo
echo "If the app menu still lacks the icon, log out and back in."
