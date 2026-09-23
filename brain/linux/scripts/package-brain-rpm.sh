#!/usr/bin/env bash
# Build a Fedora .rpm for Get Brain (double-click → Software → Install).
# Run on Linux after release binaries exist (same inputs as package-brain-release.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BRAIN="${ROOT}/brain"
BRAIN_LINUX="${BRAIN}/linux"
# Compat alias for older script sections
DESKTOP_NATIVE="${BRAIN_LINUX}"
SCRIPTS="${DESKTOP_NATIVE}/scripts"
DIST="${DESKTOP_NATIVE}/dist"
ICON_SRC="${DESKTOP_NATIVE}/resources/icons/hicolor"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: RPM builds must run on Linux (Fedora)." >&2
  exit 1
fi
if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "ERROR: rpmbuild not found. Install: sudo dnf install rpm-build rpmdevtools" >&2
  exit 1
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
      ' "${BRAIN}/Cargo.toml" 2>/dev/null || true
    )"
  fi
  printf '%s\n' "${ver:-0.0.0}"
}

find_bin() {
  local name="$1"
  local candidate
  for candidate in \
    "${BRAIN}/target/release/${name}" \
    "${HOME}/.local/bin/${name}" \
    "$(command -v "${name}" 2>/dev/null || true)"
  do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return
  done
  return 1
}

VERSION="$(resolve_version)"
# RPM version cannot have some chars; keep dotted semver.
RPM_VERSION="${VERSION}"
# RPM release. Bump this (not the version) when shipping a fix to an
# already-released build: `dnf upgrade` only moves forward on release, and
# same-version/same-release packages are refused as "already installed".
# Override with CENTURION_BRAIN_RELEASE=2.
RPM_RELEASE="${CENTURION_BRAIN_RELEASE:-1}"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
esac

DESKTOP_BIN="$(find_bin centurion-desktop)" \
  || { echo "ERROR: centurion-desktop not found." >&2; exit 1; }
REMOTE_BIN="$(find_bin centurion-remote)" \
  || { echo "ERROR: centurion-remote not found." >&2; exit 1; }
[[ -f "${SCRIPTS}/brain-launcher.sh" ]] \
  || { echo "ERROR: brain-launcher.sh missing." >&2; exit 1; }

EMBED_HITS="$(strings "${DESKTOP_BIN}" 2>/dev/null | grep -F "${VERSION}" | wc -l | tr -d ' ')"
if [[ "${EMBED_HITS}" -lt 1 ]]; then
  echo "ERROR: ${DESKTOP_BIN} does not embed version ${VERSION} — stale build." >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/centurion-brain-rpm.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

RPMBUILD="${WORK}/rpmbuild"
mkdir -p "${RPMBUILD}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
STAGE="${WORK}/stage"
mkdir -p \
  "${STAGE}/usr/bin" \
  "${STAGE}/usr/libexec/centurion" \
  "${STAGE}/usr/share/applications" \
  "${STAGE}/usr/share/centurion/brain" \
  "${STAGE}/usr/share/doc/centurion-brain" \
  "${STAGE}/usr/share/icons/hicolor"

install -m 0755 "${DESKTOP_BIN}" "${STAGE}/usr/bin/centurion-desktop"
install -m 0755 "${REMOTE_BIN}" "${STAGE}/usr/bin/centurion-remote"
install -m 0755 "${SCRIPTS}/brain-launcher.sh" "${STAGE}/usr/bin/sovereign-ai-brain"
mkdir -p "${STAGE}/usr/libexec/centurion"
install -m 0755 "${SCRIPTS}/cleanup-user-brain-launcher.sh" \
  "${STAGE}/usr/libexec/centurion/cleanup-user-brain-launcher.sh"
printf '%s\n' "${VERSION}" > "${STAGE}/usr/share/centurion/brain/VERSION"
chmod 0644 "${STAGE}/usr/share/centurion/brain/VERSION"

# Full system: Centurion AI OS (Python) + Brain — blank-machine, no terminal.
[[ -x "${SCRIPTS}/bundle-centurion-core.sh" ]] \
  || { echo "ERROR: bundle-centurion-core.sh missing." >&2; exit 1; }
"${SCRIPTS}/bundle-centurion-core.sh" "${STAGE}/usr/lib/centurion"
# Mission Deck (Focus tab) — built SPA + server.js for blank-machine installs.
"${SCRIPTS}/stage-mission-deck.sh" "${STAGE}"
# WhatsApp Baileys bridge (Node) — Telegram/Remote need no separate Node app.
"${SCRIPTS}/stage-whatsapp-bridge.sh" "${STAGE}"
cat > "${STAGE}/usr/bin/centurion" <<'EOF'
#!/bin/bash
# CLI entry for the full Fedora Brain RPM (bundled Centurion AI OS).
export CENTURION_PYTHON="${CENTURION_PYTHON:-/usr/lib/centurion/venv/bin/python}"
export CENTURION_AI_REPO="${CENTURION_AI_REPO:-/usr/lib/centurion/Centurion-AI-OS}"
exec /usr/lib/centurion/venv/bin/centurion "$@"
EOF
chmod 0755 "${STAGE}/usr/bin/centurion"


# Full hicolor set + pixmaps fallback — Software/dash/app grid all resolve
# Icon=com.centurion.desktop from these paths after gtk-update-icon-cache.
ICON_COUNT=0
if [[ -d "${ICON_SRC}" ]]; then
  for size in 16 22 24 32 48 64 128 256 512; do
    src="${ICON_SRC}/${size}x${size}/apps/com.centurion.desktop.png"
    if [[ -f "${src}" ]]; then
      mkdir -p "${STAGE}/usr/share/icons/hicolor/${size}x${size}/apps"
      install -m 0644 "${src}" \
        "${STAGE}/usr/share/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png"
      ICON_COUNT=$((ICON_COUNT + 1))
    fi
  done
  # Prefer SVG for scalable; fall back to PNG if that is what we ship.
  for scalable in \
    "${ICON_SRC}/scalable/apps/com.centurion.desktop.svg" \
    "${ICON_SRC}/scalable/apps/com.centurion.desktop.png"
  do
    if [[ -f "${scalable}" ]]; then
      mkdir -p "${STAGE}/usr/share/icons/hicolor/scalable/apps"
      install -m 0644 "${scalable}" \
        "${STAGE}/usr/share/icons/hicolor/scalable/apps/$(basename "${scalable}")"
      ICON_COUNT=$((ICON_COUNT + 1))
      break
    fi
  done
fi
if [[ "${ICON_COUNT}" -lt 1 ]]; then
  echo "ERROR: no Brain icons found under ${ICON_SRC}" >&2
  exit 1
fi

# Legacy pixmaps path — some Software / menu backends still probe here.
mkdir -p "${STAGE}/usr/share/pixmaps"
PIXMAP_SRC="${ICON_SRC}/256x256/apps/com.centurion.desktop.png"
[[ -f "${PIXMAP_SRC}" ]] || PIXMAP_SRC="${ICON_SRC}/128x128/apps/com.centurion.desktop.png"
install -m 0644 "${PIXMAP_SRC}" "${STAGE}/usr/share/pixmaps/com.centurion.desktop.png"

# AppStream — GNOME Software uses this for the install dialog icon + listing.
METAINF_SRC="${DESKTOP_NATIVE}/resources/metainfo/com.centurion.desktop.metainfo.xml"
[[ -f "${METAINF_SRC}" ]] || {
  echo "ERROR: missing ${METAINF_SRC}" >&2
  exit 1
}
mkdir -p "${STAGE}/usr/share/metainfo"
install -m 0644 "${METAINF_SRC}" \
  "${STAGE}/usr/share/metainfo/com.centurion.desktop.metainfo.xml"

cat > "${STAGE}/usr/share/applications/com.centurion.desktop.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Sovereign AI Brain
GenericName=Personal AI Brain
Comment=Your private Sovereign AI Brain
Exec=sovereign-ai-brain
Icon=com.centurion.desktop
Terminal=false
Categories=Utility;Network;
Keywords=AI;Assistant;Centurion;Sovereign;Brain;Private;
StartupNotify=true
StartupWMClass=com.centurion.desktop
X-GNOME-UsesNotifications=true
EOF
chmod 0644 "${STAGE}/usr/share/applications/com.centurion.desktop.desktop"

cat > "${STAGE}/usr/share/doc/centurion-brain/README.txt" <<EOF
Sovereign AI Brain ${VERSION} — full Centurion AI OS (Fedora RPM)

This one package installs:
  • Centurion AI OS (thinking engine)
  • Sovereign AI Brain (desktop app)
  • Focus / Mission Deck (start and manage missions)
  • Gateway surfaces: Telegram, WhatsApp, and Centurion Remote only

Customer steps (no terminal):
1. Double-click this .rpm (or open it with Software).
2. Click Install and enter your password if asked.
3. Open “Sovereign AI Brain” from Activities / Apps.
4. Open the Focus tab — first time, begin Discovery to create a mission.
5. Optional: Settings → Gateway for Telegram / WhatsApp / Remote.

Your data lives in ~/.centurion and is never wiped by this install.

Notes for advisors:
- “Potentially Unsafe / Provided by a third party” in Software is normal for
  an unsigned sideloaded RPM — not malware.
- Download size is larger than the old Brain-only RPM because the full AI
  system is included.
- Do not also run an old Smooth Transfer tar.gz after this RPM.
EOF

# Pack sources as a tarball for rpmbuild %setup-less install from buildroot copy.
tar -C "${STAGE}" -czf "${RPMBUILD}/SOURCES/centurion-brain-${RPM_VERSION}.tar.gz" .

cat > "${RPMBUILD}/SPECS/centurion-brain.spec" <<EOF
%global debug_package %{nil}
%global __os_install_post %{nil}
# Bundled tree includes scripts/docs that mention container paths (e.g.
# /command/with-contenv). Do not auto-scan those into Fedora Requires.
AutoReq:        no
AutoProv:       no

Name:           centurion-brain
Version:        ${RPM_VERSION}
Release:        ${RPM_RELEASE}%{?dist}
Summary:        Sovereign AI Brain + Centurion AI OS (full)
License:        Proprietary
URL:            https://www.1human1ai.com
BuildArch:      ${ARCH}
Source0:        centurion-brain-%{version}.tar.gz

# Runtime libs the GTK Brain links against on Fedora 41+.
Requires:       gtk4
Requires:       libadwaita
Requires:       webkitgtk6.0
Requires:       libsoup3
Requires:       hicolor-icon-theme
Requires:       python3
Requires:       nodejs

%description
Sovereign AI Brain + Centurion AI OS for Fedora (full install).

Double-click this package in Software to install everything needed for
Thinking and Focus (missions), including brain-to-brain collaboration.
Opens from your app menu as “Sovereign AI Brain”. Keeps existing
~/.centurion data if present.

%prep
%setup -c -n centurion-brain-%{version}

%build
# Prebuilt binaries — nothing to compile.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ./. %{buildroot}/

%post
# Clear Smooth Transfer user .desktop files so XDG does not prefer an old
# ~/.local/bin/centurion-desktop over this system RPM.
if [[ -x %{_libexecdir}/centurion/cleanup-user-brain-launcher.sh ]]; then
  %{_libexecdir}/centurion/cleanup-user-brain-launcher.sh >/dev/null 2>&1 || :
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || :
fi
# -f force rebuild, -t ignore missing index.theme noise; required so dash /
# Software pick up Icon=com.centurion.desktop instead of the generic cog.
touch %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
fi
if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database %{_datadir}/mime >/dev/null 2>&1 || :
fi

%postun
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || :
fi
touch %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
fi

%files
%{_bindir}/centurion-desktop
%{_bindir}/centurion-remote
%{_bindir}/sovereign-ai-brain
%{_bindir}/centurion
%{_libexecdir}/centurion/cleanup-user-brain-launcher.sh
/usr/lib/centurion
/usr/share/centurion/mission-deck
/usr/share/centurion/whatsapp-bridge
%{_datadir}/applications/com.centurion.desktop.desktop
%{_datadir}/metainfo/com.centurion.desktop.metainfo.xml
%{_datadir}/centurion/brain/VERSION
%{_datadir}/doc/centurion-brain/README.txt
%{_datadir}/pixmaps/com.centurion.desktop.png
%{_datadir}/icons/hicolor/*/apps/com.centurion.desktop.png
%{_datadir}/icons/hicolor/scalable/apps/com.centurion.desktop.*

%changelog
* $(date -u +"%a %b %d %Y") Centurion AI OS <support@1human1ai.com> - ${RPM_VERSION}-1
- Full Centurion AI OS + Brain ${RPM_VERSION}: Focus, Telegram/WhatsApp/Remote
EOF

echo "Building RPM ${RPM_VERSION} (${ARCH})…"
rpmbuild \
  --define "_topdir ${RPMBUILD}" \
  --define "_build_id_links none" \
  --define "debug_package %{nil}" \
  --nocheck \
  -bb "${RPMBUILD}/SPECS/centurion-brain.spec"

mkdir -p "${DIST}"
RPM_BUILT="$(find "${RPMBUILD}/RPMS" -type f -name 'centurion-brain-*.rpm' | head -1)"
[[ -n "${RPM_BUILT}" && -f "${RPM_BUILT}" ]] || {
  echo "ERROR: rpmbuild produced no package." >&2
  exit 1
}

OUT_NAME="centurion-brain-${VERSION}-${RPM_RELEASE}.fc.${ARCH}.rpm"
# Prefer the rpmbuild basename when it already encodes version+dist.
BASE="$(basename "${RPM_BUILT}")"
OUT_RPM="${DIST}/${BASE}"
cp -f "${RPM_BUILT}" "${OUT_RPM}"

(
  cd "${DIST}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$(basename "${OUT_RPM}")" > "$(basename "${OUT_RPM}").sha256"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$(basename "${OUT_RPM}")" > "$(basename "${OUT_RPM}").sha256"
  fi
)

# Signing — the pipeline is sign-CAPABLE, but the Centurion release key is an org
# decision that has not yet been made (no GPG secret key exists on the build box).
# When the key lands, set CENTURION_RPM_SIGN=<keyid> (and %_gpg_name in ~/.rpmmacros);
# the build will then sign with `rpm --addsign`. Until then the default stays
# unsigned and we say so loudly instead of shipping it silently.
if [[ -n "${CENTURION_RPM_SIGN:-}" ]]; then
  SIGBIN="$(command -v rpmsign 2>/dev/null || command -v rpm 2>/dev/null || true)"
  if [[ -n "${SIGBIN}" ]]; then
    echo "Signing RPM with ${CENTURION_RPM_SIGN}…"
    if "${SIGBIN}" --addsign "${OUT_RPM}" >/dev/null 2>&1; then
      echo "Signed: ${OUT_RPM}"
    else
      echo "WARNING: signing failed — RPM left unsigned." >&2
    fi
  else
    echo "WARNING: rpmsign/rpm not found — RPM left unsigned." >&2
  fi
else
  echo "WARNING: RPM is UNSIGNED (CENTURION_RPM_SIGN not set — no release key configured)." >&2
  echo "         GNOME Software will show 'Potentially Unsafe / Provided by a third party'." >&2
fi

SIZE="$(wc -c < "${OUT_RPM}" | tr -d ' ')"
echo
echo "Wrote: ${OUT_RPM} (${SIZE} bytes)"
[[ -f "${OUT_RPM}.sha256" ]] && echo "SHA256: $(cat "${OUT_RPM}.sha256")"
echo
echo "Customer path: double-click the .rpm → Software → Install → open Sovereign AI Brain."
echo "This RPM includes the full Centurion AI OS (no separate terminal install)."
echo "Publish this file from Admin → Releases (primary Get Brain artifact for Fedora)."
