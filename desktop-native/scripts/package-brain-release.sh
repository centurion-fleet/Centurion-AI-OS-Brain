#!/usr/bin/env bash
# Staff-only: build a Smooth Transfer customer archive for Admin → Releases.
# Ships Sovereign AI Brain (centurion-desktop) only — not centurion-remote.
# No mission-deck bundle (avoids AppleDouble junk from Mac copies).
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

CARGO_VERSION="$(
  awk '
    /^\[workspace\.package\]/ { in_pkg=1; next }
    /^\[/ { in_pkg=0 }
    in_pkg && /^version[[:space:]]*=/ { gsub(/"/, "", $3); print $3; exit }
  ' "${DESKTOP_NATIVE}/Cargo.toml" 2>/dev/null || true
)"
if [[ -n "${CARGO_VERSION}" && "${CARGO_VERSION}" != "${VERSION}" ]]; then
  echo "ERROR: Cargo.toml workspace version (${CARGO_VERSION}) != release label (${VERSION})." >&2
  exit 1
fi
if ! command -v strings >/dev/null 2>&1; then
  echo "ERROR: 'strings' (binutils) required for the stale-binary check." >&2
  exit 1
fi
# Count matches — avoid pipefail+SIGPIPE from grep -q closing the pipe early.
EMBED_HITS="$(strings "${DESKTOP_BIN}" 2>/dev/null | grep -F "${VERSION}" | wc -l | tr -d ' ')"
if [[ "${EMBED_HITS}" -lt 1 ]]; then
  echo "ERROR: ${DESKTOP_BIN} does not embed version ${VERSION} — stale build." >&2
  exit 1
fi
echo "  version guard: ${DESKTOP_BIN} embeds ${VERSION} ✓"

echo "Packaging Smooth Transfer release ${VERSION} (${ARCH}) — desktop only, no mission-deck"
echo "  desktop: ${DESKTOP_BIN}"

rm -rf "${STAGE}"
mkdir -p "${STAGE}/${ARCHIVE_NAME}/bin" "${STAGE}/${ARCHIVE_NAME}/icons"

install -m 0755 "${DESKTOP_BIN}" "${STAGE}/${ARCHIVE_NAME}/bin/centurion-desktop"
install -m 0755 "${SCRIPTS}/customer-install.sh" "${STAGE}/${ARCHIVE_NAME}/install.sh"
printf '%s\n' "${VERSION}" > "${STAGE}/${ARCHIVE_NAME}/VERSION"

# Double-click installer (opens a terminal so errors are visible).
cat > "${STAGE}/${ARCHIVE_NAME}/Install Brain.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Install Sovereign AI Brain
Comment=Install Brain and keep your Centurion data
Exec=bash -c 'cd "\$(dirname "\$(readlink -f "%k" 2>/dev/null || echo %k)")" && chmod +x ./install.sh && ./install.sh; echo; read -r -p "Press Enter to close… " _'
Terminal=true
Icon=com.centurion.desktop
Categories=Utility;
EOF
chmod 0755 "${STAGE}/${ARCHIVE_NAME}/Install Brain.desktop"

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

cat > "${STAGE}/${ARCHIVE_NAME}/README.txt" <<EOF
Centurion AI OS Brain — Smooth Transfer (${VERSION})

For existing Centurion users (your ~/.centurion data stays on this machine).

This archive contains Sovereign AI Brain (desktop) only.

1. Extract this archive and keep the folder.
2. Double-click "Install Brain", OR open a Terminal in this folder and run:
     chmod +x install.sh
     ./install.sh
3. Quit any old Brain / "Sovereign AI Remote" windows.
4. Open "Sovereign AI Brain" from your app menu (pin that — not Downloads).
5. You should see Transfer complete — Soul, chats, and settings are kept.

Do NOT only double-click bin/centurion-desktop — that skips install and leaves the old dock app.

If install.sh says Centurion core was not found, contact your advisor.
Updates: download the next Linux archive from Account → Get Brain, then run install again.
EOF

# Exclude AppleDouble / junk even if something slips into stage later.
mkdir -p "${DIST}"
tar -C "${STAGE}" \
  --exclude='._*' \
  --exclude='.DS_Store' \
  --exclude='*/__MACOSX/*' \
  -czf "${OUT_TGZ}" "${ARCHIVE_NAME}"

(
  cd "${DIST}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${ARCHIVE_NAME}.tar.gz" > "${ARCHIVE_NAME}.tar.gz.sha256"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${ARCHIVE_NAME}.tar.gz" > "${ARCHIVE_NAME}.tar.gz.sha256"
  fi
)

# Fail if archive still contains AppleDouble junk.
if tar -tzf "${OUT_TGZ}" | grep -E '(^|/)\._|/__MACOSX/' >/dev/null 2>&1; then
  echo "ERROR: archive still contains AppleDouble/__MACOSX junk." >&2
  exit 1
fi
if tar -tzf "${OUT_TGZ}" | grep -E 'centurion-remote|mission-deck' >/dev/null 2>&1; then
  echo "ERROR: archive must be desktop-only (no centurion-remote / mission-deck)." >&2
  exit 1
fi

SIZE="$(wc -c < "${OUT_TGZ}" | tr -d ' ')"
echo
echo "Wrote: ${OUT_TGZ} (${SIZE} bytes)"
[[ -f "${OUT_TGZ}.sha256" ]] && echo "SHA256: $(cat "${OUT_TGZ}.sha256")"
echo
echo "Next: Admin → Releases → publish this tarball, then customers use Account → Get Brain → Linux."
