#!/usr/bin/env bash
# Stage a full Centurion AI OS tree + venv into an RPM/stage root so Brain
# works on a blank Fedora machine with no terminal install.
# Usage: bundle-centurion-core.sh <STAGE_USR_LIB_CENTURION>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEST_ROOT="${1:?Usage: $0 <stage>/usr/lib/centurion}"
REPO_DST="${DEST_ROOT}/Centurion-AI-OS"
VENV_DST="${DEST_ROOT}/venv"
FINAL_VENV="/usr/lib/centurion/venv"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required to bundle Centurion core." >&2
  exit 1
fi

echo "Bundling Centurion AI OS from ${ROOT} → ${REPO_DST}"
rm -rf "${DEST_ROOT}"
mkdir -p "${REPO_DST}"

# Ship the Python tree the Brain launcher needs. Skip huge / unrelated trees.
tar -C "${ROOT}" \
  --exclude='.git' \
  --exclude='.venv' \
  --exclude='venv' \
  --exclude='node_modules' \
  --exclude='brain/target' \
  --exclude='brain/linux/dist' \
  --exclude='brain/dist' \
  --exclude='desktop-native' \
  --exclude='./web-dashboard' \
  --exclude='brain/ci-artifact' \
  --exclude='ui-tui/node_modules' \
  --exclude='website' \
  --exclude='docs' \
  --exclude='docker' \
  --exclude='tests' \
  --exclude='brain/web-dashboard/node_modules' \
  --exclude='brain/web-dashboard/dist' \
  --exclude='ios' \
  --exclude='android' \
  --exclude='desktop' \
  --exclude='build' \
  --exclude='.pytest_cache' \
  --exclude='.mypy_cache' \
  --exclude='__pycache__' \
  --exclude='desktop/src-tauri/target' \
  --exclude='*.pyc' \
  -cf - . | tar -C "${REPO_DST}" -xf -

echo "Creating venv at ${VENV_DST}…"
python3 -m venv "${VENV_DST}"
"${VENV_DST}/bin/pip" install --upgrade pip wheel setuptools
# Core + Brain-critical extras. System venv is root-owned after RPM install,
# so lazy pip install at runtime fails for customers — preinstall here.
# Messaging: Telegram + WhatsApp only (no Discord/Slack). Remote uses api_server.
"${VENV_DST}/bin/pip" install --no-cache-dir \
  "${REPO_DST}[anthropic,edge-tts,firecrawl,practice]" \
  "python-telegram-bot[webhooks]==22.6" \
  "aiohttp==3.13.4" \
  "brotlicffi==1.2.0.1" \
  "qrcode==7.4.2"

echo "Verifying bundled import…"
"${VENV_DST}/bin/python" -c \
  "import centurion; import centurion.license.enforcement; import centurion_cli.remote_bridge; import run_agent; import anthropic; import telegram; import aiohttp; import qrcode"

# Drop setuptools build/ tree left in the staged repo by pip install — keeps the
# RPM smaller and avoids PYTHONPATH confusion with a second copy of packages.
rm -rf "${REPO_DST}/build" "${REPO_DST}/centurionai_os.egg-info" \
  "${REPO_DST}/centurion_ai_os.egg-info" 2>/dev/null || true

# Relocate shebangs from the staging path to the final system path.
echo "Rewriting venv shebangs → ${FINAL_VENV}/bin/python"
shopt -s nullglob
for f in "${VENV_DST}/bin/"*; do
  [[ -f "${f}" && -x "${f}" ]] || continue
  # Only rewrite text scripts with a python shebang.
  if head -n 1 "${f}" 2>/dev/null | grep -q '^#!.*python'; then
    {
      printf '%s\n' "#!${FINAL_VENV}/bin/python"
      tail -n +2 "${f}"
    } > "${f}.new"
    mv "${f}.new" "${f}"
    chmod 0755 "${f}"
  fi
done
shopt -u nullglob

# pyvenv.cfg: keep home pointing at the system interpreter.
if [[ -f "${VENV_DST}/pyvenv.cfg" ]]; then
  python3 - <<PY
from pathlib import Path
cfg = Path("${VENV_DST}/pyvenv.cfg")
lines = []
for line in cfg.read_text(encoding="utf-8").splitlines():
    if line.startswith("home ="):
        lines.append("home = /usr/bin")
    elif line.startswith("command ="):
        continue
    else:
        lines.append(line)
cfg.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
fi

# Marker for launcher / support.
printf '%s\n' "full-rpm" > "${DEST_ROOT}/INSTALL_KIND"
chmod 0644 "${DEST_ROOT}/INSTALL_KIND"

echo "Bundled Centurion core OK ($(du -sh "${DEST_ROOT}" | awk '{print $1}'))"
