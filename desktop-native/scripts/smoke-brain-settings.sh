#!/usr/bin/env bash
# Brain Settings + Chat acceptance smoke (run on the Linux Brain).
# Verifies CLI contracts the desktop Settings / Chat UI depend on.
set -euo pipefail

CENTURION_BIN="${CENTURION_BIN:-$HOME/.local/bin/centurion}"
if [[ ! -x "${CENTURION_BIN}" ]]; then
  CENTURION_BIN="$(command -v centurion || true)"
fi
if [[ -z "${CENTURION_BIN}" ]]; then
  echo "FAIL: centurion binary not found"
  exit 1
fi

PYTHON_BIN="${CENTURION_PYTHON:-}"
if [[ -z "${PYTHON_BIN}" || ! -x "${PYTHON_BIN}" ]]; then
  for candidate in \
    "${CENTURION_AI_REPO:-}/.venv/bin/python" \
    "${CENTURION_AI_REPO:-}/venv/bin/python" \
    "$HOME/.centurion/Centurion-AI-OS/venv/bin/python" \
    "$HOME/Centurion-AI-OS/Centurion-AI-OS/.venv/bin/python" \
    "$(command -v python3 || true)"
  do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      PYTHON_BIN="${candidate}"
      break
    fi
  done
fi

pass=0
fail=0
check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: ${name}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${name}"
    fail=$((fail + 1))
  fi
}

echo "Using centurion: ${CENTURION_BIN}"
echo "Using python: ${PYTHON_BIN:-none}"

# Critical: --json must come BEFORE the subcommand.
check "provider --json status" \
  bash -c "\"${CENTURION_BIN}\" provider --json status --skip-probe | grep -q '\"ok\"'"
check "provider --json catalog" \
  bash -c "\"${CENTURION_BIN}\" provider --json catalog | grep -q 'text_models'"
check "support --json health" \
  bash -c "\"${CENTURION_BIN}\" support --json health | grep -q '\"ok\"'"
check "support --json backups" \
  bash -c "\"${CENTURION_BIN}\" support --json backups | grep -q '\"ok\"'"
check "provider apply-connector --as-backup help" \
  bash -c "\"${CENTURION_BIN}\" provider apply-connector --help 2>&1 | grep -q 'as-backup'"
check "provider remove-backup help" \
  bash -c "\"${CENTURION_BIN}\" provider remove-backup --help 2>&1 | grep -q 'slot'"

if [[ -n "${PYTHON_BIN}" ]]; then
  check "remote_bridge import" \
    bash -c "\"${PYTHON_BIN}\" -c 'import centurion_cli.remote_bridge'"
  check "oversight_get via bridge" \
    bash -c "printf '%s' '{\"id\":\"smoke\",\"action\":\"oversight_get\"}' | \"${PYTHON_BIN}\" -m centurion_cli.remote_bridge | grep -q '\"ok\"'"
  check "soul_get via bridge" \
    bash -c "printf '%s' '{\"id\":\"smoke\",\"action\":\"soul_get\"}' | \"${PYTHON_BIN}\" -m centurion_cli.remote_bridge | grep -q '\"ok\"'"
  check "memory_horizon_snapshot via bridge" \
    bash -c "printf '%s' '{\"id\":\"smoke\",\"action\":\"memory_horizon_snapshot\"}' | \"${PYTHON_BIN}\" -m centurion_cli.remote_bridge | grep -q '\"ok\"'"
  check "tools_skills_snapshot via bridge" \
    bash -c "printf '%s' '{\"id\":\"smoke\",\"action\":\"tools_skills_snapshot\"}' | \"${PYTHON_BIN}\" -m centurion_cli.remote_bridge | grep -q 'self_built'"
  check "swarm_create_board via bridge" \
    bash -c "printf '%s' '{\"id\":\"smoke\",\"action\":\"swarm_create_board\",\"name\":\"Smoke board\",\"objective\":\"smoke\"}' | \"${PYTHON_BIN}\" -m centurion_cli.remote_bridge | grep -q '\"ok\"'"
  check "swarm_snapshot via bridge" \
    bash -c "printf '%s' '{\"id\":\"smoke\",\"action\":\"swarm_snapshot\"}' | \"${PYTHON_BIN}\" -m centurion_cli.remote_bridge | grep -q '\"ok\"'"
  check "skills.allow_public_hub default false" \
    bash -c "\"${PYTHON_BIN}\" -c 'from centurion_cli.config import DEFAULT_CONFIG; assert DEFAULT_CONFIG[\"skills\"].get(\"allow_public_hub\") is False'"
else
  echo "SKIP: python bridge checks (no interpreter)"
fi

echo
echo "Result: ${pass} passed, ${fail} failed"
echo "Manual UI checklist on Titus:"
echo "  [ ] Thinking Service status readable; Change + Restore work"
echo "  [ ] Backup Thinking Change: set Backup #1 with connector + key; Clear works"
echo "  [ ] Skills & tools: self-built vs reference; Ask Centurion to create seeds Chat"
echo "  [ ] Collaborations New board (+ optional mission id); honest board-saved copy"
echo "  [ ] Channels Remote: Pair / Show QR; Fleet peer empty-state copy"
echo "  [ ] Chat mode teaching line under pills"
echo "  [ ] Prefer Focus on decisions hidden; Scheduled/Plugins say View only"
echo "  [ ] Autonomy / Soul / Memory Horizon / Oversight save + refresh"
echo "  [ ] Health Check / Support Bundle / Look up Support Code"
echo "  [ ] Chat tab: bubbles (not terminal); send gets a reply"
if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
