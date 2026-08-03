#!/usr/bin/env bash
# Customer Smooth Transfer installer — ships inside centurion-brain-*.tar.gz.
# Installs Sovereign AI Brain (centurion-desktop) + optional pairing helper.
# Never deletes Centurion data.
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
  # Install-Brain (GUI) owns the error dialog when CENTURION_GUI_INSTALL=1.
  if [[ "${CENTURION_GUI_INSTALL:-}" != "1" ]]; then
    if command -v zenity >/dev/null 2>&1; then
      zenity --error --title="Centurion AI OS Brain" --width=420 --text="$*" 2>/dev/null || true
    elif command -v notify-send >/dev/null 2>&1; then
      notify-send "Centurion AI OS Brain" "$*" 2>/dev/null || true
    fi
    # Keep GUI "Run as Program" terminals readable (they close on exit).
    if [[ -t 0 || -t 1 ]]; then
      echo
      read -r -p "Press Enter to close… " _ || true
    fi
  fi
  exit 1
}

ok_dialog() {
  local msg="$1"
  echo "$msg"
  # Install-Brain shows the success dialog when CENTURION_GUI_INSTALL=1.
  if [[ "${CENTURION_GUI_INSTALL:-}" == "1" ]]; then
    return 0
  fi
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
install -m 0755 "${ARCHIVE_ROOT}/bin/centurion-desktop" "${BIN_DIR}/centurion-desktop" \
  || die "Could not install centurion-desktop into ${BIN_DIR}."
if [[ -x "${ARCHIVE_ROOT}/bin/centurion-remote" ]]; then
  install -m 0755 "${ARCHIVE_ROOT}/bin/centurion-remote" "${BIN_DIR}/centurion-remote" \
    || die "Could not install centurion-remote into ${BIN_DIR}."
  echo "Installed pairing helper: ${BIN_DIR}/centurion-remote"
fi

ICON_ABS=""
if [[ -d "${ARCHIVE_ROOT}/icons" ]]; then
  # Null-delimited find — archive paths often contain spaces (e.g. "… (2)/…").
  while IFS= read -r -d '' src; do
    rel="${src#"${ARCHIVE_ROOT}/icons/"}"
    dest="${ICON_DIR}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    install -m 0644 "${src}" "${dest}" \
      || die "Could not install icon: ${src}"
  done < <(find "${ARCHIVE_ROOT}/icons" -type f -name 'com.centurion.desktop.png' -print0 2>/dev/null)

  # Absolute path fallback — some docks ignore hicolor until logout/cache refresh.
  for size in 256 128 64 48; do
    candidate="${ICON_DIR}/${size}x${size}/apps/com.centurion.desktop.png"
    if [[ -f "${candidate}" ]]; then
      ICON_ABS="${candidate}"
      break
    fi
  done
  if [[ -n "${ICON_ABS}" ]]; then
    mkdir -p "${HOME}/.local/share/pixmaps"
    install -m 0644 "${ICON_ABS}" "${HOME}/.local/share/pixmaps/com.centurion.desktop.png" || true
  fi
fi

MISSION_DECK_DST="${SHARE_DIR}/mission-deck"
DESKTOP_ICON="com.centurion.desktop"
if [[ -n "${ICON_ABS}" ]]; then
  DESKTOP_ICON="${ICON_ABS}"
fi

cat > "${APP_DIR}/com.centurion.desktop.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sovereign AI Brain
GenericName=Personal AI Brain
Comment=Your private Sovereign AI Brain
Exec=env CENTURION_PYTHON=${PYTHON_BIN} CENTURION_AI_REPO=${AI_REPO} CENTURION_HOME=${CENTURION_HOME_DIR} CENTURION_MISSION_DECK_DIR=${MISSION_DECK_DST} ${BIN_DIR}/centurion-desktop
Icon=${DESKTOP_ICON}
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
  gtk-update-icon-cache -f -t "${ICON_DIR}" || true
fi
if command -v xdg-icon-resource >/dev/null 2>&1 && [[ -n "${ICON_ABS}" ]]; then
  xdg-icon-resource install --novendor --size 256 "${ICON_ABS}" com.centurion.desktop 2>/dev/null || true
fi
if command -v xdg-desktop-menu >/dev/null 2>&1; then
  xdg-desktop-menu forceupdate 2>/dev/null || true
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

ok_dialog "Installed Sovereign AI Brain ${VERSION}.

Open it from the Applications menu as \"Sovereign AI Brain\".
Remove any old pin from Downloads or \"Sovereign AI Remote\"."
# Stable one-line marker for the GUI Install-Brain success screen.
echo "Installed Sovereign AI Brain ${VERSION}."
echo
echo "Installed:"
echo "  ${BIN_DIR}/centurion-desktop"
[[ -x "${BIN_DIR}/centurion-remote" ]] && echo "  ${BIN_DIR}/centurion-remote"
echo "  Python: ${PYTHON_BIN}"
echo "  Repo:   ${AI_REPO}"
echo "  Home:   ${CENTURION_HOME_DIR}"
echo "  Log:    ${LOG_FILE}"

# Ensure license activation can reach the customer portal (do not wipe other keys).
CENTURION_HOME_DIR="${CENTURION_HOME_DIR}" python3 - <<'PY'
import os
import pathlib
try:
    import yaml
except ImportError:
    raise SystemExit(0)
cfg_path = pathlib.Path(os.environ["CENTURION_HOME_DIR"]) / "config.yaml"
data = {}
if cfg_path.is_file():
    try:
        data = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
    except Exception:
        data = {}
if not isinstance(data, dict):
    data = {}
lic = data.get("license") if isinstance(data.get("license"), dict) else {}
lic = dict(lic)
lic.setdefault("enabled", True)
lic.setdefault("enforcement", False)
lic.setdefault("server_url", "https://www.1human1ai.com/api/v1")
lic.setdefault("portal_url", "https://www.1human1ai.com")
data["license"] = lic
cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(yaml.safe_dump(data, default_flow_style=False, sort_keys=False), encoding="utf-8")
print(f"License portal configured in {cfg_path}")
PY
