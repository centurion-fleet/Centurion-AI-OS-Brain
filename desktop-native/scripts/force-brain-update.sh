#!/usr/bin/env bash
# One-shot recovery when Settings → Update cannot stash / pull (Legio chicken-egg).
# Forces the Centurion checkout to origin/main, then rebuilds Sovereign AI Brain.
set -euo pipefail

if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -n "${CENTURION_AI_REPO:-}" && -d "${CENTURION_AI_REPO}/.git" ]]; then
  ROOT="${CENTURION_AI_REPO}"
fi

echo "Forcing Centurion checkout to origin/main:"
echo "  ${ROOT}"
git -C "${ROOT}" fetch origin
git -C "${ROOT}" checkout main
git -C "${ROOT}" reset --hard origin/main
# Leave nested sibling clones alone; drop other untracked dirt that blocks rebuilds.
# Keep desktop-native/patches — Fedora 44 glib-rs compat patches live there.
git -C "${ROOT}" clean -fd \
  -e personal-centurion-help-center \
  -e .venv -e venv \
  -e desktop-native/patches

echo
echo "Rebuilding Sovereign AI Brain…"
exec bash "${ROOT}/desktop-native/scripts/install-user.sh"
