#!/usr/bin/env bash
set -euo pipefail

ATTEMPTS="${DM_LESSONMELD_DMG_VERIFY_ATTEMPTS:-5}"
DELAY_SECONDS="${DM_LESSONMELD_DMG_VERIFY_DELAY_SECONDS:-5}"
APP_NAME="Digital Meld LessonMeld"
EXPECTED_BUNDLE_ID="io.digitalmeld.dm-lessonmeld"

if [[ "$#" -eq 0 ]]; then
  echo "usage: scripts/verify-dmg.sh <dmg-path> [dmg-path ...]" >&2
  exit 2
fi

for dmg_path in "$@"; do
  if [[ ! -f "${dmg_path}" ]]; then
    echo "error: DMG not found: ${dmg_path}" >&2
    exit 1
  fi

  verified=0
  for ((attempt = 1; attempt <= ATTEMPTS; attempt += 1)); do
    if hdiutil verify "${dmg_path}"; then
      verified=1
      break
    fi

    if [[ "${attempt}" -eq "${ATTEMPTS}" ]]; then
      echo "error: hdiutil verify failed after ${ATTEMPTS} attempts: ${dmg_path}" >&2
      exit 1
    fi

    echo "hdiutil verify failed for ${dmg_path}; retrying in ${DELAY_SECONDS}s (${attempt}/${ATTEMPTS})..." >&2
    sleep "${DELAY_SECONDS}"
  done

  if [[ "${verified}" != "1" ]]; then
    echo "error: hdiutil verify did not complete for ${dmg_path}" >&2
    exit 1
  fi

  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/dm-lessonmeld-dmg.XXXXXX")"
  mounted=0
  cleanup() {
    if [[ "${mounted}" == "1" ]]; then
      hdiutil detach "${mount_dir}" -quiet || true
    fi
    rm -rf "${mount_dir}"
  }
  trap cleanup EXIT

  hdiutil attach "${dmg_path}" -readonly -nobrowse -mountpoint "${mount_dir}" >/dev/null
  mounted=1

  app_path="${mount_dir}/${APP_NAME}.app"
  if [[ ! -d "${app_path}" ]]; then
    echo "error: DMG is missing ${APP_NAME}.app" >&2
    exit 1
  fi

  if [[ ! -L "${mount_dir}/Applications" ]]; then
    echo "error: DMG is missing Applications symlink" >&2
    exit 1
  fi

  if [[ "$(readlink "${mount_dir}/Applications")" != "/Applications" ]]; then
    echo "error: DMG Applications symlink does not point to /Applications" >&2
    exit 1
  fi

  info_plist="${app_path}/Contents/Info.plist"
  if [[ ! -f "${info_plist}" ]]; then
    echo "error: DMG app bundle is missing Contents/Info.plist" >&2
    exit 1
  fi

  plutil -lint "${info_plist}" >/dev/null
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"
  if [[ "${bundle_id}" != "${EXPECTED_BUNDLE_ID}" ]]; then
    echo "error: DMG app bundle id ${bundle_id} does not match ${EXPECTED_BUNDLE_ID}" >&2
    exit 1
  fi

  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${info_plist}")"
  if [[ -z "${executable}" || ! -x "${app_path}/Contents/MacOS/${executable}" ]]; then
    echo "error: DMG app executable is missing or not executable" >&2
    exit 1
  fi

  cleanup
  trap - EXIT
done
