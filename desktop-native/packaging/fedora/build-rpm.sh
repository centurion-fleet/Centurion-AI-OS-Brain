#!/usr/bin/env bash
set -euo pipefail

# Build a source tarball and RPM for centurion-desktop from the repo root.
# Usage: desktop-native/packaging/fedora/build-rpm.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERSION="$(grep '^version' "${ROOT}/desktop-native/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
NAME="centurion-desktop"
TARBALL="${NAME}-${VERSION}.tar.gz"
BUILD_DIR="${ROOT}/desktop-native/packaging/fedora/rpmbuild"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/SOURCES" "${BUILD_DIR}/SPECS" "${BUILD_DIR}/BUILD" "${BUILD_DIR}/RPMS" "${BUILD_DIR}/SRPMS"

tar -C "${ROOT}" \
  --exclude='desktop-native/target' \
  --exclude='.git' \
  -czf "${BUILD_DIR}/SOURCES/${TARBALL}" .

cp "${ROOT}/desktop-native/packaging/fedora/centurion-desktop.spec" "${BUILD_DIR}/SPECS/"

rpmbuild -ba "${BUILD_DIR}/SPECS/centurion-desktop.spec" \
  --define "_topdir ${BUILD_DIR}" \
  --define "version ${VERSION}"

echo
echo "RPM build complete."
find "${BUILD_DIR}/RPMS" -name '*.rpm' -print
