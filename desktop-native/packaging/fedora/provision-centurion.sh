#!/usr/bin/env bash
set -euo pipefail

# Provision Centurion Desktop + encrypted iPhone service on Fedora hardware.
# Usage:
#   ./provision-centurion.sh [--local-rpm PATH] [--interface IFACE] [--verify]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_RPM=""
LAN_INTERFACE=""
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-rpm)
      LOCAL_RPM="${2:-}"
      shift 2
      ;;
    --interface)
      LAN_INTERFACE="${2:-}"
      shift 2
      ;;
    --verify)
      VERIFY_ONLY=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this as the Centurion desktop user, not root." >&2
  exit 2
fi

verify_installation() {
  local failures=0

  echo "Verifying Centurion remote service…"
  if systemctl --user is-active --quiet centurion-remote.service; then
    echo "  ✓ centurion-remote.service is active"
  else
    echo "  ✗ centurion-remote.service is not active" >&2
    failures=$((failures + 1))
  fi

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | grep -q ':9119'; then
      echo "  ✓ TCP port 9119 is listening"
    else
      echo "  ✗ TCP port 9119 is not listening" >&2
      failures=$((failures + 1))
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --zone=trusted --list-services 2>/dev/null | grep -q centurion-remote; then
      echo "  ✓ firewalld trusted zone includes centurion-remote"
    else
      echo "  ✗ firewalld trusted zone missing centurion-remote" >&2
      failures=$((failures + 1))
    fi
    if firewall-cmd --zone=trusted --list-services 2>/dev/null | grep -q mdns; then
      echo "  ✓ firewalld trusted zone includes mdns"
    else
      echo "  ✗ firewalld trusted zone missing mdns" >&2
      failures=$((failures + 1))
    fi
  fi

  if command -v centurion-remote >/dev/null 2>&1; then
    if centurion-remote devices --json >/dev/null 2>&1; then
      echo "  ✓ centurion-remote devices --json"
    else
      echo "  ✗ centurion-remote devices --json failed" >&2
      failures=$((failures + 1))
    fi
  fi

  if command -v centurion >/dev/null 2>&1; then
    echo "  ✓ Centurion AI OS CLI is installed"
  else
    echo "  ! Centurion AI OS CLI not found — Chat and agent turns need the Python core"
  fi

  echo
  echo "Physical iPhone E2E checklist:"
  echo "  1. iPhone and Fedora box on the same Wi‑Fi"
  echo "  2. iPhone: Connect tab → discover → connect → send chat"
  echo "  3. Desktop: Devices → approve pending fingerprint"
  echo "  4. Revoke device → reconnect should require re-approval"
  echo "  5. Restart centurion-remote → iPhone should reconnect with pinned server key"

  return "${failures}"
}

if [[ "${VERIFY_ONLY}" -eq 1 ]]; then
  verify_installation
  exit $?
fi

if [[ -n "${LOCAL_RPM}" ]]; then
  echo "Installing local RPM: ${LOCAL_RPM}"
  sudo dnf install -y "${LOCAL_RPM}"
else
  echo "Installing Centurion Desktop (native GTK shell + encrypted iPhone service)…"
  sudo dnf install -y centurion-desktop
fi

if ! command -v centurion >/dev/null 2>&1; then
  echo
  echo "Centurion AI OS (Python core) is not installed yet."
  echo "Install it before using Chat or remote agent turns:"
  echo "  pip install --user -e ${ROOT}"
  echo "  centurion setup"
  echo
fi

if [[ -z "${LAN_INTERFACE}" ]]; then
  LAN_INTERFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
fi

echo "Opening trusted-zone firewall rules for local discovery and iPhone pairing…"
sudo firewall-cmd --permanent --zone=trusted --add-service=mdns
sudo firewall-cmd --permanent --zone=trusted --add-service=centurion-remote
if [[ -n "${LAN_INTERFACE}" ]]; then
  echo "Assigning ${LAN_INTERFACE} to firewalld trusted zone…"
  sudo firewall-cmd --permanent --zone=trusted --change-interface="${LAN_INTERFACE}"
else
  echo "Warning: could not detect LAN interface — assign your Wi‑Fi NIC to the trusted zone manually." >&2
fi
sudo firewall-cmd --reload

if command -v loginctl >/dev/null 2>&1; then
  sudo loginctl enable-linger "${USER}" || true
fi

systemctl --user daemon-reload
systemctl --user enable --now centurion-remote.service

echo
echo "Centurion Desktop is installed."
echo "  • Open Centurion from the application menu"
echo "  • Use Chat for local conversation (embedded centurion --tui)"
echo "  • Use Devices to approve your iPhone fingerprint"
echo
verify_installation
