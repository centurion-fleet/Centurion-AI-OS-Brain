#!/usr/bin/env bash
# Build WhatsApp Baileys bridge and stage it for the Fedora Brain RPM.
# Usage: stage-whatsapp-bridge.sh <STAGE_ROOT>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BRIDGE_SRC="${ROOT}/scripts/whatsapp-bridge"
STAGE_ROOT="${1:?Usage: $0 <rpm-stage-root>}"
DEST="${STAGE_ROOT}/usr/share/centurion/whatsapp-bridge"

if [[ ! -f "${BRIDGE_SRC}/bridge.js" || ! -f "${BRIDGE_SRC}/package.json" ]]; then
  echo "ERROR: whatsapp-bridge missing at ${BRIDGE_SRC}" >&2
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm required to build WhatsApp bridge (dnf install nodejs)." >&2
  exit 1
fi

echo "Staging WhatsApp bridge…"
rm -rf "${DEST}"
mkdir -p "${DEST}"
# Copy sources (not any host node_modules).
tar -C "${BRIDGE_SRC}" \
  --exclude='node_modules' \
  --exclude='.git' \
  -cf - . | tar -C "${DEST}" -xf -

(
  cd "${DEST}"
  if [[ -f package-lock.json ]]; then
    npm ci --omit=dev --no-audit --no-fund
  else
    npm install --omit=dev --no-audit --no-fund
  fi
)
[[ -f "${DEST}/bridge.js" && -d "${DEST}/node_modules" ]] || {
  echo "ERROR: WhatsApp bridge stage incomplete" >&2
  exit 1
}

echo "Staged WhatsApp bridge → ${DEST} ($(du -sh "${DEST}" | awk '{print $1}'))"
