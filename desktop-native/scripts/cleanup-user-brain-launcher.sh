#!/usr/bin/env bash
# Remove leftover Smooth Transfer (user-local) Brain launchers so the system
# RPM entry wins. XDG prefers ~/.local/share/applications over /usr/share.
# Safe to run as root (cleans all /home/*) or as the logged-in user.
set -euo pipefail

clean_one_home() {
  local home="$1"
  [[ -n "${home}" && -d "${home}" ]] || return 0
  local desk="${home}/.local/share/applications/com.centurion.desktop.desktop"
  local bin_local="${home}/.local/bin/centurion-desktop"
  local removed=0

  if [[ -f "${desk}" ]]; then
    rm -f "${desk}" && removed=1
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "${home}/.local/share/applications" >/dev/null 2>&1 || true
    fi
  fi

  # Stale user-local binary from older Smooth Transfer installs — remove only
  # when the system Brain from the RPM is present.
  if [[ -x /usr/bin/centurion-desktop || -x /usr/bin/sovereign-ai-brain ]]; then
    if [[ -f "${bin_local}" ]]; then
      rm -f "${bin_local}" && removed=1
    fi
  fi

  if [[ "${removed}" -eq 1 ]]; then
    echo "Removed leftover user Brain launcher under ${home}"
  fi
}

if [[ "${EUID}" -eq 0 ]]; then
  for home in /home/* /root; do
    [[ -d "${home}" ]] || continue
    clean_one_home "${home}"
  done
else
  clean_one_home "${HOME}"
fi
