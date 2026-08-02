#!/usr/bin/env bash
# Staff-only: build a Smooth Transfer customer archive for Admin → Releases.
# Run on a private Linux build host after binaries exist (install-user.sh or cargo).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_NATIVE="${ROOT}/desktop-native"
SCRIPTS="${DESKTOP_NATIVE}/scripts"
DIST="${DESKTOP_NATIVE}/dist"
STAGE="${DIST}/stage"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "WARNING: Customer Get Brain archives must be built on Linux." >&2
  echo "  This host is $(uname -s)/$(uname -m) — publish only linux-* builds from a Linux host." >&2
  if [[ "${CENTURION_ALLOW_NON_LINUX_PACKAGE:-}" != "1" ]]; then
    echo "ERROR: refusing non-Linux package (set CENTURION_ALLOW_NON_LINUX_PACKAGE=1 to override for local smoke)." >&2
    exit 1
  fi
fi

resolve_version() {
  if [[ -n "${CENTURION_BRAIN_VERSION:-}" ]]; then
    printf '%s\n' "${CENTURION_BRAIN_VERSION}"
    return
  fi
  python3 - <<'PY' 2>/dev/null || true
from pathlib import Path
root = Path(__file__).resolve().parents[0] if False else None
PY
  local ver
  ver="$(
    python3 -c "import pathlib; t=pathlib.Path('${ROOT}/centurion_cli/__init__.py').read_text();
import re; m=re.search(r'__version__\\s*=\\s*[\"\\']([^\"\\']+)', t); print(m.group(1) if m else '')" \
      2>/dev/null || true
  )"
  if [[ -z "${ver}" ]]; then
    ver="$(
      awk '
        /^\[workspace\.package\]/ { in_pkg=1; next }
        /^\[/ { in_pkg=0 }
        in_pkg && /^version[[:space:]]*=/ { gsub(/"/, "", $3); print $3; exit }
      ' "${DESKTOP_NATIVE}/Cargo.toml" 2>/dev/null || true
    )"
  fi
  printf '%s\n' "${ver:-0.0.0}"
}

VERSION="$(resolve_version)"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
esac
ARCHIVE_NAME="centurion-brain-${VERSION}-linux-${ARCH}"
OUT_TGZ="${DIST}/${ARCHIVE_NAME}.tar.gz"

find_bin() {
  local name="$1"
  local candidate
  for candidate in \
    "${DESKTOP_NATIVE}/target/release/${name}" \
    "${HOME}/.local/bin/${name}" \
    "$(command -v "${name}" 2>/dev/null || true)"
  do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return
  done
  return 1
}

DESKTOP_BIN="$(find_bin centurion-desktop)" \
  || { echo "ERROR: centurion-desktop not found. Run desktop-native/scripts/install-user.sh first." >&2; exit 1; }
REMOTE_BIN="$(find_bin centurion-remote)" \
  || { echo "ERROR: centurion-remote not found. Run desktop-native/scripts/install-user.sh first." >&2; exit 1; }

# --- Stale-binary guard: refuse to label a binary with a version it wasn't built as ---
# The desktop bakes env!("CARGO_PKG_VERSION") into the ELF. VERSION must match the
# Cargo workspace version AND the string embedded in the binary — otherwise we'd
# ship a stale binary labeled as a new release.
CARGO_VERSION="$(
  awk '
    /^\[workspace\.package\]/ { in_pkg=1; next }
    /^\[/ { in_pkg=0 }
    in_pkg && /^version[[:space:]]*=/ { gsub(/"/, "", $3); print $3; exit }
  ' "${DESKTOP_NATIVE}/Cargo.toml" 2>/dev/null || true
)"
if [[ -n "${CARGO_VERSION}" && "${CARGO_VERSION}" != "${VERSION}" ]]; then
  echo "ERROR: Cargo.toml workspace version (${CARGO_VERSION}) != release label (${VERSION})." >&2
  echo "  Bump desktop-native/Cargo.toml [workspace.package] version to ${VERSION} and rebuild." >&2
  exit 1
fi
if ! command -v strings >/dev/null 2>&1; then
  echo "ERROR: 'strings' (binutils) required for the stale-binary check." >&2
  exit 1
fi
if ! strings "${DESKTOP_BIN}" 2>/dev/null | grep -Fxq "${VERSION}"; then
  echo "ERROR: ${DESKTOP_BIN} does not embed version ${VERSION} — stale build." >&2
  echo "  Rebuild the desktop binary from this source tree (install-user.sh) before packaging." >&2
  exit 1
fi
echo "  version guard: ${DESKTOP_BIN} embeds ${VERSION} ✓"

echo "Packaging Smooth Transfer release ${VERSION} (${ARCH})"
echo "  desktop: ${DESKTOP_BIN}"
echo "  remote:  ${REMOTE_BIN}"

rm -rf "${STAGE}"
mkdir -p "${STAGE}/${ARCHIVE_NAME}/bin" \
  "${STAGE}/${ARCHIVE_NAME}/icons" \
  "${STAGE}/${ARCHIVE_NAME}/systemd"

install -m 0755 "${DESKTOP_BIN}" "${STAGE}/${ARCHIVE_NAME}/bin/centurion-desktop"
install -m 0755 "${REMOTE_BIN}" "${STAGE}/${ARCHIVE_NAME}/bin/centurion-remote"
install -m 0755 "${SCRIPTS}/customer-install.sh" "${STAGE}/${ARCHIVE_NAME}/install.sh"
install -m 0644 "${SCRIPTS}/customer-centurion-remote.service" \
  "${STAGE}/${ARCHIVE_NAME}/systemd/centurion-remote.service"

printf '%s\n' "${VERSION}" > "${STAGE}/${ARCHIVE_NAME}/VERSION"

# Icons (keep archive lean — skip huge sizes if needed).
ICON_SRC="${DESKTOP_NATIVE}/resources/icons/hicolor"
if [[ -d "${ICON_SRC}" ]]; then
  for size in 16 22 24 32 48 64 128 256; do
    src="${ICON_SRC}/${size}x${size}/apps/com.centurion.desktop.png"
    if [[ -f "${src}" ]]; then
      mkdir -p "${STAGE}/${ARCHIVE_NAME}/icons/${size}x${size}/apps"
      install -m 0644 "${src}" \
        "${STAGE}/${ARCHIVE_NAME}/icons/${size}x${size}/apps/com.centurion.desktop.png"
    fi
  done
  scalable="${ICON_SRC}/scalable/apps/com.centurion.desktop.png"
  if [[ -f "${scalable}" ]]; then
    mkdir -p "${STAGE}/${ARCHIVE_NAME}/icons/scalable/apps"
    install -m 0644 "${scalable}" \
      "${STAGE}/${ARCHIVE_NAME}/icons/scalable/apps/com.centurion.desktop.png"
  fi
fi

# Optional Mission Deck assets if already built and small enough.
MISSION_SRC="${HOME}/.local/share/centurion/mission-deck"
if [[ -d "${MISSION_SRC}/dist" ]]; then
  mkdir -p "${STAGE}/${ARCHIVE_NAME}/mission-deck"
  cp -R "${MISSION_SRC}/dist" "${STAGE}/${ARCHIVE_NAME}/mission-deck/" 2>/dev/null || true
  [[ -f "${MISSION_SRC}/server.js" ]] && cp "${MISSION_SRC}/server.js" "${STAGE}/${ARCHIVE_NAME}/mission-deck/" || true
  [[ -f "${MISSION_SRC}/package.json" ]] && cp "${MISSION_SRC}/package.json" "${STAGE}/${ARCHIVE_NAME}/mission-deck/" || true
fi

cat > "${STAGE}/${ARCHIVE_NAME}/README.txt" <<EOF
Centurion AI OS Brain — Smooth Transfer (${VERSION})

For existing Centurion users (your ~/.centurion data stays on this machine).

1. Keep this folder after extracting the archive.
2. Double-click install.sh, or run:  ./install.sh
3. Open "Sovereign AI Brain" from your app menu.
4. You should see Transfer complete — Soul, chats, and settings are kept.

No git, cargo, or advisor terminal session is required.

If install.sh says Centurion core was not found, contact your advisor.
Updates: download the next Linux archive from Account → Get Brain, then run install.sh again.
EOF

mkdir -p "${DIST}"
tar -C "${STAGE}" -czf "${OUT_TGZ}" "${ARCHIVE_NAME}"
(
  cd "${DIST}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${ARCHIVE_NAME}.tar.gz" > "${ARCHIVE_NAME}.tar.gz.sha256"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${ARCHIVE_NAME}.tar.gz" > "${ARCHIVE_NAME}.tar.gz.sha256"
  fi
)

SIZE="$(wc -c < "${OUT_TGZ}" | tr -d ' ')"
echo
echo "Wrote: ${OUT_TGZ} (${SIZE} bytes)"
[[ -f "${OUT_TGZ}.sha256" ]] && echo "SHA256: $(cat "${OUT_TGZ}.sha256")"
if [[ "${SIZE}" -gt $((40 * 1000 * 1000)) ]]; then
  echo "NOTE: archive is over ~40MB — use storage-path publish in Admin if upload limit applies."
fi
echo
echo "Next: Admin → Releases → publish this tarball, then customers use Account → Get Brain → Linux."
