#!/usr/bin/env bash
# Customer Smooth Transfer installer — ships inside centurion-brain-*.tar.gz.
# Installs Sovereign AI Brain (centurion-desktop) only. Never deletes Centurion data.
set -euo pipefail

ARCHIVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor"
SHARE_DIR="${HOME}/.local/share/centurion"
LOG_FILE="${HOME}/.centurion/logs/smooth-transfer-install.log"

die() {
  echo "ERROR: $*" >&2
  mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  echo "ERROR: $*" >> "${LOG_FILE}" 2>/dev/null || true
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="Centurion AI OS Brain" --width=420 --text="$*" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Centurion AI OS Brain" "$*" 2>/dev/null || true
  fi
  exit 1
}

ok_dialog() {
  local msg="$1"
  echo "$msg"
  if command -v zenity >/dev/null 2>&1; then
    zenity --info --title="Centurion AI OS Brain" --width=420 --text="$msg" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Centurion AI OS Brain" "$msg" 2>/dev/null || true
  fi
}

resolve_centurion_home() {
  if [[ -n "${CENTURION_HOME:-}" && -d "${CENTURION_HOME}" ]]; then
    printf '%s\n' "${CENTURION_HOME}"
    return
  fi
  local root="${HOME}/.centurion"
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

find_python_brain() {
  if [[ -n "${CENTURION_PYTHON:-}" && -x "${CENTURION_PYTHON}" ]]; then
    if "${CENTURION_PYTHON}" -c "import centurion_cli.remote_bridge" >/dev/null 2>&1; then
      printf '%s\n' "${CENTURION_PYTHON}"
      return
    fi
  fi
  if command -v centurion >/dev/null 2>&1; then
    local shebang
    shebang="$(command -v centurion)"
    for candidate in \
      "$(dirname "${shebang}")/python" \
      "$(dirname "${shebang}")/python3" \
      "${HOME}/.centurion/Centurion-AI-OS/venv/bin/python" \
      "${HOME}/.centurion/Centurion-AI-OS/.venv/bin/python"
    do
      if [[ -x "${candidate}" ]] \
        && "${candidate}" -c "import centurion_cli.remote_bridge" >/dev/null 2>&1; then
        printf '%s\n' "${candidate}"
        return
      fi
    done
  fi
  local candidate
  for candidate in \
    "${HOME}/.centurion/Centurion-AI-OS/venv/bin/python" \
    "${HOME}/.centurion/Centurion-AI-OS/.venv/bin/python" \
    "${HOME}/.centurion/venv/bin/python" \
    "${HOME}/Centurion-AI-OS/.venv/bin/python" \
    "${HOME}/Centurion-AI-OS/venv/bin/python" \
    "${HOME}/src/Centurion-AI-OS/.venv/bin/python" \
    "${HOME}/src/Centurion-AI-OS/venv/bin/python"
  do
    if [[ -x "${candidate}" ]] \
      && "${candidate}" -c "import centurion_cli.remote_bridge" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  return 1
}

find_ai_repo() {
  local py="$1"
  local candidate
  for candidate in \
    "${CENTURION_AI_REPO:-}" \
    "${HOME}/.centurion/Centurion-AI-OS" \
    "${HOME}/Centurion-AI-OS" \
    "${HOME}/src/Centurion-AI-OS"
  do
    [[ -n "${candidate}" ]] || continue
    if [[ -f "${candidate}/centurion_cli/remote_bridge.py" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  local root
  root="$(cd "$(dirname "${py}")/../.." 2>/dev/null && pwd || true)"
  if [[ -f "${root}/centurion_cli/remote_bridge.py" ]]; then
    printf '%s\n' "${root}"
    return
  fi
  root="$(cd "$(dirname "${py}")/../../.." 2>/dev/null && pwd || true)"
  if [[ -f "${root}/centurion_cli/remote_bridge.py" ]]; then
    printf '%s\n' "${root}"
    return
  fi
  return 1
}

mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
{
  echo "=== Smooth Transfer install $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
  echo "ARCHIVE_ROOT=${ARCHIVE_ROOT}"
} >> "${LOG_FILE}" 2>/dev/null || true

[[ -x "${ARCHIVE_ROOT}/bin/centurion-desktop" ]] \
  || die "Missing centurion-desktop in this archive. Re-download Get Brain for Linux."

CENTURION_HOME_DIR="$(resolve_centurion_home)"
mkdir -p "${CENTURION_HOME_DIR}"

PYTHON_BIN="$(find_python_brain)" || die \
  "Centurion core not found on this machine. Contact your advisor — install.sh only adds the Brain app and keeps your existing Centurion data."

AI_REPO="$(find_ai_repo "${PYTHON_BIN}")" || die \
  "Centurion core not found on this machine. Contact your advisor — install.sh only adds the Brain app and keeps your existing Centurion data."

for protected in config.yaml .env SOUL.md; do
  if [[ -e "${CENTURION_HOME_DIR}/${protected}" ]]; then
    echo "Keeping existing ${CENTURION_HOME_DIR}/${protected}"
  fi
done

mkdir -p "${BIN_DIR}" "${APP_DIR}" "${ICON_DIR}" "${SHARE_DIR}"
install -m 0755 "${ARCHIVE_ROOT}/bin/centurion-desktop" "${BIN_DIR}/centurion-desktop"

if [[ -d "${ARCHIVE_ROOT}/icons" ]]; then
  # shellcheck disable=SC2044
  for src in $(find "${ARCHIVE_ROOT}/icons" -type f -name 'com.centurion.desktop.png' 2>/dev/null); do
    rel="${src#${ARCHIVE_ROOT}/icons/}"
    dest="${ICON_DIR}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    install -m 0644 "${src}" "${dest}"
  done
fi

MISSION_DECK_DST="${SHARE_DIR}/mission-deck"

cat > "${APP_DIR}/com.centurion.desktop.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sovereign AI Brain
GenericName=Personal AI Brain
Comment=Your private Sovereign AI Brain
Exec=env CENTURION_PYTHON=${PYTHON_BIN} CENTURION_AI_REPO=${AI_REPO} CENTURION_HOME=${CENTURION_HOME_DIR} CENTURION_MISSION_DECK_DIR=${MISSION_DECK_DST} ${BIN_DIR}/centurion-desktop
Icon=com.centurion.desktop
Terminal=false
Categories=Utility;Network;
Keywords=AI;Assistant;Centurion;Sovereign;Brain;Private;
StartupNotify=true
StartupWMClass=com.centurion.desktop
EOF
chmod 0644 "${APP_DIR}/com.centurion.desktop.desktop"

# Remove stale dock names from older installs (do not delete the new Brain entry).
if [[ -f "${APP_DIR}/centurion-remote.desktop" ]]; then
  rm -f "${APP_DIR}/centurion-remote.desktop" || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${APP_DIR}" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f "${ICON_DIR}" || true
fi

printf '1\n' > "${CENTURION_HOME_DIR}/smooth_transfer_pending"
VERSION_FILE="${ARCHIVE_ROOT}/VERSION"
VERSION="unknown"
[[ -f "${VERSION_FILE}" ]] && VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}" || true)"
BUILT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)"
cat > "${CENTURION_HOME_DIR}/desktop-build.json" <<EOF
{
  "version": "${VERSION}",
  "git_rev": "smooth-transfer",
  "git_branch": "release",
  "built_at": "${BUILT_AT}",
  "repo_root": "${AI_REPO}",
  "binary": "${BIN_DIR}/centurion-desktop",
  "install": "smooth-transfer"
}
EOF
chmod 0644 "${CENTURION_HOME_DIR}/desktop-build.json" || true

ok_dialog "Installed Sovereign AI Brain ${VERSION}. Open it from the app menu — remove any old 'Sovereign AI Remote' dock pin."
echo
echo "Installed:"
echo "  ${BIN_DIR}/centurion-desktop"
echo "  Python: ${PYTHON_BIN}"
echo "  Repo:   ${AI_REPO}"
echo "  Home:   ${CENTURION_HOME_DIR}"
echo "  Log:    ${LOG_FILE}"
