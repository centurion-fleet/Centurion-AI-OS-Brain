#!/usr/bin/env bash
# Build Mission Deck (web-dashboard) and stage it for the Fedora Brain RPM.
# Usage: stage-mission-deck.sh <STAGE_ROOT>   # e.g. …/stage → installs under usr/share/…
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEB="${ROOT}/web-dashboard"
STAGE_ROOT="${1:?Usage: $0 <rpm-stage-root>}"
DEST="${STAGE_ROOT}/usr/share/centurion/mission-deck"

if [[ ! -f "${WEB}/package.json" || ! -f "${WEB}/server.js" ]]; then
  echo "ERROR: web-dashboard missing at ${WEB}" >&2
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm required to build Mission Deck (dnf install nodejs)." >&2
  exit 1
fi

echo "Building Mission Deck (web-dashboard)…"
(
  cd "${WEB}"
  if [[ -f package-lock.json ]]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi
  npm run build
)
[[ -d "${WEB}/dist" ]] || {
  echo "ERROR: web-dashboard build produced no dist/" >&2
  exit 1
}

rm -rf "${DEST}"
mkdir -p "${DEST}/dist"
install -m 0644 "${WEB}/server.js" "${DEST}/server.js"
install -m 0644 "${WEB}/package.json" "${DEST}/package.json"
# Production server uses Node builtins only — ship dist/, not node_modules.
cp -a "${WEB}/dist/." "${DEST}/dist/"

echo "Staged Mission Deck → ${DEST} ($(du -sh "${DEST}" | awk '{print $1}'))"
