#!/bin/bash
# Centurion — release a TCP port before a service binds it.
#
# WHY THIS EXISTS
# ---------------
# A restart is not a stop. `systemctl --user restart <unit>` only stops what the
# unit owns. A process left over from an older install — in the field, the
# retired user-local build — is NOT owned by the unit, survives the restart, and
# keeps the port. Every new start then dies with EADDRINUSE, and because the unit
# carries `Restart=on-failure` / `RestartSec=3` that becomes a crash loop:
# **672 failed starts, one every three seconds**, measured on a real machine
# 28 Sep 2026 (Os { code: 98, kind: AddrInUse }, port 9119).
#
# This runs as `ExecStartPre`, so the port is free BEFORE the service starts —
# whoever holds it. If it cannot be freed the script exits non-zero, so the
# fault is ONE loud failure instead of a silent loop burning CPU every three
# seconds on a machine somebody paid for.
#
# Only processes owned by the invoking user can be signalled, and only that
# class of leftover exists in this scenario (the stale holder is a user-local
# centurion-remote). A holder we cannot signal is reported, not ignored.
#
# DETECTION IS /proc/net/tcp, NOT `ss`.
# An earlier version trusted `ss` and treated "ss produced no output" as "port
# is free" — so an `ss` that was present but failing made the script exit 0 and
# leave the stale holder running. That is a success-shaped lie, and in this
# script it is the exact failure being fixed. /proc/net/tcp is always there, and
# reading kernel state directly cannot be wrong about what is listening.
#
# Usage: centurion-free-port.sh [port] [grace_seconds]
#   port           default 9119 (the away-from-home remote rail)
#   grace_seconds  default 6   (SIGTERM window before escalating to SIGKILL)

set -u

PORT="${1:-9119}"
GRACE_SECS="${2:-6}"

log() { printf 'centurion-free-port: %s\n' "$*" >&2; }

port_hex() { printf '%04X' "${PORT}"; }

# Inode of the socket LISTENING on ${PORT}, or empty. /proc/net/tcp covers IPv4,
# /proc/net/tcp6 covers IPv6; either can be the one holding the port.
listen_inode() {
  local hex file inode
  hex="$(port_hex)"
  for file in /proc/net/tcp /proc/net/tcp6; do
    [[ -r "${file}" ]] || continue
    # $2 = local_address (hex LE addr + ":" + hex port), $4 = 0A (LISTEN),
    # $10 = inode. The ":$hex" suffix match anchors the port exactly.
    inode="$(awk -v p=":${hex}" \
      'NR > 1 && $2 ~ p"$" && $4 == "0A" { print $10; exit }' "${file}" 2>/dev/null)"
    if [[ -n "${inode}" ]]; then
      printf '%s' "${inode}"
      return 0
    fi
  done
  return 0
}

port_free() { [[ -z "$(listen_inode)" ]]; }

# PIDs of this user's processes holding the socket with the given inode.
pids_for_inode() {
  local want="socket:[$1]" fd owner found=""
  for fd in /proc/[0-9]*/fd/*; do
    [[ "$(readlink "${fd}" 2>/dev/null)" == "${want}" ]] || continue
    owner="$(basename "$(dirname "$(dirname "${fd}")")")"
    [[ "${owner}" =~ ^[0-9]+$ ]] && found="${found} ${owner}"
  done
  printf '%s' "${found}" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' '
}

main() {
  local inode pids waited

  inode="$(listen_inode)"
  if [[ -z "${inode}" ]]; then
    exit 0   # nothing is listening — nothing to do, no noise in the journal
  fi

  # Loop: the holder must be re-resolved each time, because a process can exit
  # and a different one take the port between our two passes.
  for (( waited = 0; waited < GRACE_SECS * 2; waited++ )); do
    inode="$(listen_inode)"
    [[ -z "${inode}" ]] && { log "port ${PORT} released"; exit 0; }
    pids="$(pids_for_inode "${inode}" | xargs -r echo)"

    if [[ -z "${pids}" ]]; then
      log "port ${PORT} is listening (socket inode ${inode}) but no signalable holder was found — refusing to start"
      exit 1
    fi

    if [[ "${waited}" -eq 0 ]]; then
      log "port ${PORT} held by pid(s): ${pids} — asking them to stop"
    fi
    # shellcheck disable=SC2086
    kill -TERM ${pids} 2>/dev/null || true
    sleep 0.5
  done

  # A wedged process will not honour SIGTERM. Leaving it in place all but
  # guarantees the next bind fails, so escalate — decisively, and once.
  log "still held after ${GRACE_SECS}s — escalating to SIGKILL"
  inode="$(listen_inode)"
  if [[ -n "${inode}" ]]; then
    pids="$(pids_for_inode "${inode}" | xargs -r echo)"
    if [[ -n "${pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 ${pids} 2>/dev/null || true
    fi
  fi

  for (( waited = 0; waited < 10; waited++ )); do
    if port_free; then
      log "port ${PORT} released after SIGKILL"
      exit 0
    fi
    sleep 0.5
  done

  log "REFUSING TO START: port ${PORT} is still held after SIGTERM and SIGKILL"
  exit 1
}

main "$@"
