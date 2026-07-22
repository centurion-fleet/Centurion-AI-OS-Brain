#!/usr/bin/env bash
# Restart centurion-remote with the checkout as TERMINAL_CWD (iPhone chat bridge).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${HOME}/.local/bin/centurion-remote"
export CENTURION_HOME="${CENTURION_HOME:-${HOME}/.centurion}"
export TERMINAL_CWD="${ROOT}"

if [[ ! -x "${BIN}" ]]; then
  echo "centurion-remote not found at ${BIN}. Run desktop-native/scripts/install-user.sh first." >&2
  exit 1
fi

systemctl --user stop centurion-remote.service 2>/dev/null || true
echo "Starting centurion-remote with TERMINAL_CWD=${TERMINAL_CWD}"
exec "${BIN}" serve --name "Sovereign AI Brain"
