#!/usr/bin/env bash
# Idempotent Fedora 44 / glib-rs compat patches for Sovereign AI Brain.
# Safe to run on every install-user.sh — no-ops when already applied.
set -euo pipefail

ROOT="${1:-}"
if [[ -z "${ROOT}" || ! -d "${ROOT}" ]]; then
  echo "usage: apply-fedora-patches.sh <CENTURION_AI_REPO>" >&2
  exit 1
fi

CHAT_PAGE="${ROOT}/desktop-native/centurion-desktop/src/chat_page.rs"
if [[ ! -f "${CHAT_PAGE}" ]]; then
  echo "skip fedora patches: missing ${CHAT_PAGE}"
  exit 0
fi

# Fixes are now in-tree on main. Only apply the legacy patch file when the
# old patterns are still present (older checkouts / partial merges).
need_list_cast=0
need_css_slice=0
if grep -q 'list_index\.push(start\.unwrap_or(1));' "${CHAT_PAGE}" 2>/dev/null; then
  need_list_cast=1
fi
if grep -q 'css_classes(&class_refs)' "${CHAT_PAGE}" 2>/dev/null; then
  need_css_slice=1
fi

if [[ "${need_list_cast}" -eq 0 && "${need_css_slice}" -eq 0 ]]; then
  echo "fedora glib-rs compat: already applied (in-tree)"
  exit 0
fi

PATCH_FILE="${ROOT}/desktop-native/patches/fedora-44-glib-compat.patch"
if [[ ! -f "${PATCH_FILE}" ]]; then
  echo "WARNING: need fedora fixes but patch missing at ${PATCH_FILE}" >&2
  # Fall through to inline sed fixes below.
fi

if [[ -f "${PATCH_FILE}" ]]; then
  if patch -p1 --forward --dry-run -d "${ROOT}" < "${PATCH_FILE}" >/dev/null 2>&1; then
    patch -p1 --forward -d "${ROOT}" < "${PATCH_FILE}"
    echo "fedora glib-rs compat: applied ${PATCH_FILE}"
    exit 0
  fi
fi

# Inline fallback when the unified diff no longer matches (line drift).
if [[ "${need_list_cast}" -eq 1 ]]; then
  sed -i 's/list_index\.push(start\.unwrap_or(1));/list_index.push(start.unwrap_or(1) as u32);/g' "${CHAT_PAGE}"
fi
if [[ "${need_css_slice}" -eq 1 ]]; then
  sed -i 's/\.css_classes(&class_refs)/.css_classes(class_refs.as_slice())/g' "${CHAT_PAGE}"
fi
echo "fedora glib-rs compat: applied inline fallback"
exit 0
