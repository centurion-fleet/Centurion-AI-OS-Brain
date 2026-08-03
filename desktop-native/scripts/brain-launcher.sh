#!/usr/bin/env bash
# Sovereign AI Brain launcher — installed by the Fedora .rpm (and optional tar).
# Discovers the user's existing Centurion at runtime so Chat/Thinking use their
# real settings. Never wipes CENTURION_HOME data.
set -euo pipefail

VERSION_FILE="/usr/share/centurion/brain/VERSION"
DESKTOP_BIN="${CENTURION_DESKTOP_BIN:-/usr/bin/centurion-desktop}"
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

seed_license_config() {
  local home_dir="$1"
  CENTURION_HOME_DIR="${home_dir}" python3 - <<'PY' 2>/dev/null || true
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
PY
}

stamp_smooth_transfer() {
  local home_dir="$1"
  local repo="$2"
  local version="unknown"
  if [[ -f "${VERSION_FILE}" ]]; then
    version="$(tr -d '[:space:]' < "${VERSION_FILE}" || true)"
  fi
  mkdir -p "${home_dir}"
  local stamp="${home_dir}/desktop-build.json"
  if [[ ! -f "${stamp}" ]] || ! grep -q '"install": "smooth-transfer"' "${stamp}" 2>/dev/null; then
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
  seed_license_config "${home_dir}"
}

mkdir -p "${LOG_DIR}" 2>/dev/null || true
{
  echo "=== brain-launcher $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
} >> "${LOG_FILE}" 2>/dev/null || true

[[ -x "${DESKTOP_BIN}" ]] || die_gui \
  "Sovereign AI Brain is not installed correctly (missing ${DESKTOP_BIN}). Reinstall from Get Brain."

CENTURION_HOME_DIR="$(resolve_centurion_home)"
mkdir -p "${CENTURION_HOME_DIR}"

PYTHON_BIN="$(find_python_brain)" || die_gui \
  "Centurion core was not found on this computer. Contact your advisor — Brain keeps your existing Centurion data and needs that install to think and chat."

AI_REPO="$(find_ai_repo "${PYTHON_BIN}")" || die_gui \
  "Centurion core was not found on this computer. Contact your advisor — Brain keeps your existing Centurion data and needs that install to think and chat."

stamp_smooth_transfer "${CENTURION_HOME_DIR}" "${AI_REPO}"

export CENTURION_HOME="${CENTURION_HOME_DIR}"
export CENTURION_PYTHON="${PYTHON_BIN}"
export CENTURION_AI_REPO="${AI_REPO}"

exec "${DESKTOP_BIN}" "$@"
