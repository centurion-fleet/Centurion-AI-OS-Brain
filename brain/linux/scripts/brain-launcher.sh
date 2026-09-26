#!/usr/bin/env bash
# Sovereign AI Brain launcher — installed by the Fedora .rpm (and optional tar).
# Discovers the user's existing Centurion at runtime so Chat/Thinking use their
# real settings. Never wipes CENTURION_HOME data.
set -euo pipefail

VERSION_FILE="/usr/share/centurion/brain/VERSION"
BRAIN_VERSION_FILE="/usr/share/centurion/BRAIN_VERSION"
DESKTOP_BIN="${CENTURION_DESKTOP_BIN:-/usr/bin/centurion-desktop}"
# Full Fedora RPM ships Centurion core here (no separate terminal install).
BUNDLED_ROOT="/usr/lib/centurion"
BUNDLED_PYTHON="${BUNDLED_ROOT}/venv/bin/python"
BUNDLED_REPO="${BUNDLED_ROOT}/Centurion-AI-OS"
LOG_DIR="${HOME}/.centurion/logs"
LOG_FILE="${LOG_DIR}/brain-launcher.log"

die_gui() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  mkdir -p "${LOG_DIR}" 2>/dev/null || true
  echo "ERROR: $msg" >> "${LOG_FILE}" 2>/dev/null || true
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="Sovereign AI Brain" --width=440 --text="$msg" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Sovereign AI Brain" "$msg" 2>/dev/null || true
  fi
  exit 1
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

resolve_brain_version() {
  local version=""
  if [[ -f "${BRAIN_VERSION_FILE}" ]]; then
    version="$(tr -d '[:space:]' < "${BRAIN_VERSION_FILE}" || true)"
  elif command -v rpm >/dev/null 2>&1; then
    version="$(rpm -q --qf '%{VERSION}' centurion-brain 2>/dev/null || true)"
  fi
  if [[ -n "${version}" ]]; then
    printf '%s\n' "${version}"
  else
    printf '%s\n' "unknown"
  fi
}

cached_python_brain() {
  local cache_file="$1"
  local brain_version="$2"
  [[ -f "${cache_file}" ]] || return 1

  local cached_version=""
  local cached_path=""
  {
    IFS= read -r cached_version || return 1
    IFS= read -r cached_path || return 1
  } < "${cache_file}"
  [[ "${cached_version}" == "${brain_version}" ]] || return 1
  if [[ -n "${CENTURION_PYTHON:-}" && "${cached_path}" != "${CENTURION_PYTHON}" ]]; then
    return 1
  fi
  [[ -n "${cached_path}" && -x "${cached_path}" ]] || return 1
  # Need both: bridge module and the ``centurion`` package (license/fleet).
  "${cached_path}" -c "import centurion_cli.remote_bridge, centurion.license.enforcement" \
    >/dev/null 2>&1 || return 1
  printf '%s\n' "${cached_path}"
}

cache_python_brain() {
  local cache_file="$1"
  local brain_version="$2"
  local python_path="$3"
  local cache_dir
  cache_dir="$(dirname "${cache_file}")"
  mkdir -p "${cache_dir}"
  local tmp="${cache_file}.tmp.$$"
  printf '%s\n%s\n' "${brain_version}" "${python_path}" > "${tmp}"
  chmod 0600 "${tmp}" || true
  mv -f "${tmp}" "${cache_file}"
}

python_imports_brain_core() {
  local py="$1"
  [[ -x "${py}" ]] || return 1
  "${py}" -c "import centurion_cli.remote_bridge, centurion.license.enforcement" \
    >/dev/null 2>&1
}

find_python_brain() {
  if [[ -n "${CENTURION_PYTHON:-}" ]] && python_imports_brain_core "${CENTURION_PYTHON}"; then
    printf '%s\n' "${CENTURION_PYTHON}"
    return
  fi
  # Prefer the core bundled inside the full Fedora RPM (blank-machine install).
  if python_imports_brain_core "${BUNDLED_PYTHON}"; then
    printf '%s\n' "${BUNDLED_PYTHON}"
    return
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
      if python_imports_brain_core "${candidate}"; then
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
    if python_imports_brain_core "${candidate}"; then
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
    "${BUNDLED_REPO}" \
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

seed_license_config() {
  local home_dir="$1"
  CENTURION_HOME_DIR="${home_dir}" python3 - <<'PY' 2>/dev/null
import os
import pathlib
import secrets
try:
    import yaml
except ImportError:
    raise SystemExit(0)

home = pathlib.Path(os.environ["CENTURION_HOME_DIR"])
cfg_path = home / "config.yaml"
env_path = home / ".env"
data = {}
if cfg_path.is_file():
    try:
        data = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
    except Exception:
        data = {}
if not isinstance(data, dict):
    data = {}

# License: portal wiring ready, enforcement OFF for customers for now.
lic = data.get("license") if isinstance(data.get("license"), dict) else {}
lic = dict(lic)
lic.setdefault("enabled", True)
lic["enforcement"] = False  # keep codes off until advisor turns them on
lic.setdefault("server_url", "https://www.1human1ai.com/api/v1")
lic.setdefault("portal_url", "https://www.1human1ai.com")
data["license"] = lic

# Gateway: only Telegram, WhatsApp, Remote (api_server) stubs.
gw = data.get("gateway") if isinstance(data.get("gateway"), dict) else {}
gw = dict(gw)
platforms = gw.get("platforms") if isinstance(gw.get("platforms"), dict) else {}
platforms = dict(platforms)
for name, defaults in (
    ("telegram", {"enabled": False}),
    ("whatsapp", {"enabled": False}),
    ("api_server", {"enabled": True}),
):
    block = platforms.get(name) if isinstance(platforms.get(name), dict) else {}
    block = dict(block)
    for k, v in defaults.items():
        block.setdefault(k, v)
    if name == "whatsapp":
        extra = block.get("extra") if isinstance(block.get("extra"), dict) else {}
        extra = dict(extra)
        extra.setdefault(
            "bridge_script",
            "/usr/share/centurion/whatsapp-bridge/bridge.js",
        )
        block["extra"] = extra
    if name == "api_server":
        extra = block.get("extra") if isinstance(block.get("extra"), dict) else {}
        extra = dict(extra)
        extra.setdefault("host", "127.0.0.1")
        extra.setdefault("port", 18789)
        block["extra"] = extra
    platforms[name] = block
gw["platforms"] = platforms
data["gateway"] = gw

cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(yaml.safe_dump(data, default_flow_style=False, sort_keys=False), encoding="utf-8")

# Ensure Remote (api_server) has a local key in .env when missing.
def _env_has(key: str) -> bool:
    if not env_path.is_file():
        return False
    try:
        for line in env_path.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith(f"{key}="):
                return True
    except Exception:
        return False
    return False

lines_to_add = []
if not _env_has("API_SERVER_ENABLED"):
    lines_to_add.append("API_SERVER_ENABLED=true")
if not _env_has("API_SERVER_KEY"):
    lines_to_add.append(f"API_SERVER_KEY={secrets.token_urlsafe(32)}")
if lines_to_add:
    env_path.parent.mkdir(parents=True, exist_ok=True)
    existing = ""
    if env_path.is_file():
        existing = env_path.read_text(encoding="utf-8")
        if existing and not existing.endswith("\n"):
            existing += "\n"
    env_path.write_text(existing + "\n".join(lines_to_add) + "\n", encoding="utf-8")
PY
}

# Has a Centurion actually been used on this machine? This is the honest test for
# whether there is anything to transfer. A fresh install has nothing, and telling a
# first-time owner that their "Soul, chats and settings are still on this machine"
# is a false statement — it also suppresses the first-run Welcome, because the
# transfer confirmation marks the Welcome as seen. Checked BEFORE any seeding.
home_has_prior_use() {
  local home_dir="$1"
  [[ -s "${home_dir}/config.yaml" ]] && return 0
  [[ -s "${home_dir}/.env" ]] && return 0
  [[ -f "${home_dir}/agent_name" ]] && return 0
  [[ -d "${home_dir}/memories" ]] && return 0
  [[ -d "${home_dir}/vault" ]] && return 0
  [[ -d "${home_dir}/sessions" ]] && return 0
  return 1
}

stamp_smooth_transfer() {
  local home_dir="$1"
  local repo="$2"
  local brain_version="$3"
  local version="unknown"
  if [[ -f "${VERSION_FILE}" ]]; then
    version="$(tr -d '[:space:]' < "${VERSION_FILE}" || true)"
  fi
  mkdir -p "${home_dir}"
  local stamp="${home_dir}/desktop-build.json"
  if { [[ ! -f "${stamp}" ]] || ! grep -q '"install": "smooth-transfer"' "${stamp}" 2>/dev/null; } \
     && home_has_prior_use "${home_dir}"; then
    printf '1\n' > "${home_dir}/smooth_transfer_pending"
  fi
  local built_at
  built_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)"
  cat > "${stamp}" <<EOF
{
  "version": "${version}",
  "git_rev": "smooth-transfer",
  "git_branch": "release",
  "built_at": "${built_at}",
  "repo_root": "${repo}",
  "binary": "${DESKTOP_BIN}",
  "install": "smooth-transfer"
}
EOF
  chmod 0644 "${stamp}" || true
  local run_dir="${home_dir}/run"
  local seed_stamp="${run_dir}/brain-seed.stamp"
  local seeded_version=""
  if [[ -f "${seed_stamp}" ]]; then
    seeded_version="$(tr -d '\r\n' < "${seed_stamp}" || true)"
  fi
  if [[ "${seeded_version}" != "${brain_version}" ]]; then
    mkdir -p "${run_dir}"
    if seed_license_config "${home_dir}"; then
      local tmp="${seed_stamp}.tmp.$$"
      printf '%s\n' "${brain_version}" > "${tmp}"
      chmod 0600 "${tmp}" || true
      mv -f "${tmp}" "${seed_stamp}"
    fi
  fi
}

mkdir -p "${LOG_DIR}" 2>/dev/null || true
{
  echo "=== brain-launcher $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
} >> "${LOG_FILE}" 2>/dev/null || true

# ------------------------------------------------------------ phone tunnel unit
# Defect fixed 26 Sep 2026 (Steve White, both machines, via Adrian):
# The phone-tunnel unit can be left on disk by an older install — pointing at a
# user-local binary and a development interpreter. Nothing ever corrected it, so
# the service kept running old code while the packaged binary sat unread, and
# every reinstall met the same dead button. Reinstalling the package does not fix
# this: the unit lives in the owner's home, not in the package.
#
# A unit is only ours to correct in its ExecStart *target*. Anything the owner's
# install added — advertise host, working directory, ReadWritePaths — is left
# exactly as written, and the previous file is kept beside it.
REMOTE_UNIT_NAME="centurion-remote.service"
REMOTE_UNIT_SHIPPED="/usr/lib/systemd/user/${REMOTE_UNIT_NAME}"
REMOTE_UNIT_USER="${HOME}/.config/systemd/user/${REMOTE_UNIT_NAME}"
REMOTE_UNIT_EXEC='/usr/bin/centurion-remote serve --name "Sovereign AI Brain"'

refresh_remote_unit() {
  local changed=0
  if [[ ! -f "${REMOTE_UNIT_USER}" ]]; then
    # No unit of the owner's own: adopt the packaged one so the tunnel exists.
    [[ -r "${REMOTE_UNIT_SHIPPED}" ]] || return 0
    mkdir -p "$(dirname "${REMOTE_UNIT_USER}")" 2>/dev/null || return 0
    cp -f "${REMOTE_UNIT_SHIPPED}" "${REMOTE_UNIT_USER}" 2>/dev/null || return 0
    changed=1
  elif grep -qE '^ExecStart=/usr/bin/centurion-remote' "${REMOTE_UNIT_USER}"; then
    return 0
  else
    local tmp
    tmp="$(mktemp)" || return 0
    awk -v exec="${REMOTE_UNIT_EXEC}" '
      /^ExecStart=/ && length($0) > length("ExecStart=") { print "ExecStart=" exec; next }
      { print }
    ' "${REMOTE_UNIT_USER}" > "${tmp}" 2>/dev/null || { rm -f "${tmp}"; return 0; }
    # Refuse to write a file that still has no packaged ExecStart in it.
    if ! grep -qE '^ExecStart=/usr/bin/centurion-remote' "${tmp}"; then
      rm -f "${tmp}"
      return 0
    fi
    cp -f "${REMOTE_UNIT_USER}" "${REMOTE_UNIT_USER}.pre-refresh.bak" 2>/dev/null || true
    cat "${tmp}" > "${REMOTE_UNIT_USER}" 2>/dev/null || { rm -f "${tmp}"; return 0; }
    rm -f "${tmp}"
    changed=1
  fi

  [[ "${changed}" -eq 1 ]] || return 0

  # The file on disk is the fix; systemd only needs telling when it can be
  # reached. Without a session bus the next login picks the file up anyway.
  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user try-restart "${REMOTE_UNIT_NAME}" >/dev/null 2>&1 || true
  fi
  printf '%s remote unit refreshed -> %s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${REMOTE_UNIT_EXEC}" >> "${LOG_FILE}" 2>/dev/null || true
}

refresh_remote_unit || true

# Drop leftover Smooth Transfer user .desktop so this system Brain is what
# the menu/dash actually launches (otherwise an older ~/.local binary wins).
if [[ -x /usr/libexec/centurion/cleanup-user-brain-launcher.sh ]]; then
  /usr/libexec/centurion/cleanup-user-brain-launcher.sh >/dev/null 2>&1 || true
elif [[ -f "${HOME}/.local/share/applications/com.centurion.desktop.desktop" ]]; then
  rm -f "${HOME}/.local/share/applications/com.centurion.desktop.desktop" || true
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
  fi
fi

[[ -x "${DESKTOP_BIN}" ]] || die_gui \
  "Sovereign AI Brain is not installed correctly (missing ${DESKTOP_BIN}). Reinstall from Get Brain."

CENTURION_HOME_DIR="$(resolve_centurion_home)"
mkdir -p "${CENTURION_HOME_DIR}"
BRAIN_VERSION="$(resolve_brain_version)"
PYTHON_CACHE="${CENTURION_HOME_DIR}/run/brain-python.path"

if ! PYTHON_BIN="$(cached_python_brain "${PYTHON_CACHE}" "${BRAIN_VERSION}")"; then
  PYTHON_BIN="$(find_python_brain)" || die_gui \
    "Centurion core was not found on this computer. Contact your advisor — Brain keeps your existing Centurion data and needs that install to think and chat."
  cache_python_brain "${PYTHON_CACHE}" "${BRAIN_VERSION}" "${PYTHON_BIN}"
fi

AI_REPO="$(find_ai_repo "${PYTHON_BIN}")" || die_gui \
  "Centurion core was not found on this computer. Contact your advisor — Brain keeps your existing Centurion data and needs that install to think and chat."

stamp_smooth_transfer "${CENTURION_HOME_DIR}" "${AI_REPO}" "${BRAIN_VERSION}"

export CENTURION_HOME="${CENTURION_HOME_DIR}"
export CENTURION_PYTHON="${PYTHON_BIN}"
export CENTURION_AI_REPO="${AI_REPO}"

# Focus / Mission Deck (React) — full RPM ships this under /usr/share.
if [[ -z "${CENTURION_MISSION_DECK_DIR:-}" ]]; then
  for deck in \
    /usr/share/centurion/mission-deck \
    "${AI_REPO}/brain/web-dashboard" \
    "${HOME}/.local/share/centurion/mission-deck"
  do
    if [[ -f "${deck}/server.js" ]]; then
      export CENTURION_MISSION_DECK_DIR="${deck}"
      break
    fi
  done
fi

# Customer Brain: only Telegram, WhatsApp, and Remote Control gateway surfaces.
export CENTURION_GATEWAY_ALLOWED_PLATFORMS="${CENTURION_GATEWAY_ALLOWED_PLATFORMS:-telegram,whatsapp,api_server}"
if [[ -z "${CENTURION_WHATSAPP_BRIDGE_DIR:-}" && -f /usr/share/centurion/whatsapp-bridge/bridge.js ]]; then
  export CENTURION_WHATSAPP_BRIDGE_DIR="/usr/share/centurion/whatsapp-bridge"
fi

exec "${DESKTOP_BIN}" "$@"
