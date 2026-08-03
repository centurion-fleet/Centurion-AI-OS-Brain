#!/usr/bin/env bash
# Build a Fedora .rpm for Get Brain (double-click → Software → Install).
# Run on Linux after release binaries exist (same inputs as package-brain-release.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_NATIVE="${ROOT}/desktop-native"
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
      ' "${DESKTOP_NATIVE}/Cargo.toml" 2>/dev/null || true
    )"
  fi
  printf '%s\n' "${ver:-0.0.0}"
}

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

VERSION="$(resolve_version)"
# RPM version cannot have some chars; keep dotted semver.
RPM_VERSION="${VERSION}"
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
printf '%s\n' "${VERSION}" > "${STAGE}/usr/share/centurion/brain/VERSION"
chmod 0644 "${STAGE}/usr/share/centurion/brain/VERSION"

if [[ -d "${ICON_SRC}" ]]; then
  for size in 16 22 24 32 48 64 128 256; do
    src="${ICON_SRC}/${size}x${size}/apps/com.centurion.desktop.png"
    if [[ -f "${src}" ]]; then
      mkdir -p "${STAGE}/usr/share/icons/hicolor/${size}x${size}/apps"
      install -m 0644 "${src}" \
        "${STAGE}/usr/share/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png"
    fi
  done
fi

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
EOF
chmod 0644 "${STAGE}/usr/share/applications/com.centurion.desktop.desktop"

cat > "${STAGE}/usr/share/doc/centurion-brain/README.txt" <<EOF
Sovereign AI Brain ${VERSION} (Fedora RPM)

1. Double-click this .rpm (or open it with Software).
2. Click Install and enter your password if asked.
3. Open “Sovereign AI Brain” from Activities / Apps.
4. Your existing Centurion data in ~/.centurion is kept.

Chat and Thinking use the Centurion already on this computer.
If Brain says Centurion core was not found, contact your advisor.
EOF

# Pack sources as a tarball for rpmbuild %setup-less install from buildroot copy.
tar -C "${STAGE}" -czf "${RPMBUILD}/SOURCES/centurion-brain-${RPM_VERSION}.tar.gz" .

cat > "${RPMBUILD}/SPECS/centurion-brain.spec" <<EOF
Name:           centurion-brain
Version:        ${RPM_VERSION}
Release:        1%{?dist}
Summary:        Sovereign AI Brain desktop for Centurion
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

%description
Sovereign AI Brain — the Centurion desktop app for Fedora.

Install via Software (double-click this package). Opens from your app menu
as “Sovereign AI Brain”. Uses your existing Centurion install and never
wipes ~/.centurion data.

%prep
%setup -c -n centurion-brain-%{version}

%build
# Prebuilt binaries — nothing to compile.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ./. %{buildroot}/

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
fi

%postun
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
fi

%files
%{_bindir}/centurion-desktop
%{_bindir}/centurion-remote
%{_bindir}/sovereign-ai-brain
%{_datadir}/applications/com.centurion.desktop.desktop
%{_datadir}/centurion/brain/VERSION
%{_datadir}/doc/centurion-brain/README.txt
%{_datadir}/icons/hicolor/*/apps/com.centurion.desktop.png

%changelog
* $(date -u +"%a %b %d %Y") Centurion AI OS <support@1human1ai.com> - ${RPM_VERSION}-1
- Sovereign AI Brain ${RPM_VERSION} Smooth Transfer for Fedora
EOF

echo "Building RPM ${RPM_VERSION} (${ARCH})…"
rpmbuild \
  --define "_topdir ${RPMBUILD}" \
  --define "_build_id_links none" \
  -bb "${RPMBUILD}/SPECS/centurion-brain.spec"

mkdir -p "${DIST}"
RPM_BUILT="$(find "${RPMBUILD}/RPMS" -type f -name 'centurion-brain-*.rpm' | head -1)"
[[ -n "${RPM_BUILT}" && -f "${RPM_BUILT}" ]] || {
  echo "ERROR: rpmbuild produced no package." >&2
  exit 1
}

OUT_NAME="centurion-brain-${VERSION}-1.fc.${ARCH}.rpm"
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

SIZE="$(wc -c < "${OUT_RPM}" | tr -d ' ')"
echo
echo "Wrote: ${OUT_RPM} (${SIZE} bytes)"
[[ -f "${OUT_RPM}.sha256" ]] && echo "SHA256: $(cat "${OUT_RPM}.sha256")"
echo
echo "Customer path: double-click the .rpm → Software → Install → open Sovereign AI Brain."
echo "Publish this file from Admin → Releases (primary Get Brain artifact for Fedora)."
