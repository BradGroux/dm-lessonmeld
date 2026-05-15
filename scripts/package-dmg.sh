#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Digital Meld LessonMeld"
APP_DIR="${ROOT_DIR}/Packaging/${APP_NAME}.app"
DIST_DIR="${ROOT_DIR}/.build/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/Packaging/Info.plist")"
DMG_PATH="${DIST_DIR}/dm-lessonmeld-${VERSION}-macos.dmg"
STAGING_DIR="${DIST_DIR}/dmg-root"
VOLUME_NAME="LessonMeld ${VERSION}"
REQUIRE_NOTARIZATION="${DM_LESSONMELD_REQUIRE_NOTARIZATION:-0}"

notarize_args=()
if [[ -n "${NOTARIZE_PROFILE:-}" ]]; then
  notarize_args=(--keychain-profile "${NOTARIZE_PROFILE}")
elif [[ -n "${NOTARIZE_KEY_PATH:-}" || -n "${NOTARIZE_KEY_ID:-}" || -n "${NOTARIZE_ISSUER_ID:-}" ]]; then
  if [[ -z "${NOTARIZE_KEY_PATH:-}" || -z "${NOTARIZE_KEY_ID:-}" || -z "${NOTARIZE_ISSUER_ID:-}" ]]; then
    echo "error: NOTARIZE_KEY_PATH, NOTARIZE_KEY_ID, and NOTARIZE_ISSUER_ID must be set together." >&2
    exit 1
  fi
  notarize_args=(--key "${NOTARIZE_KEY_PATH}" --key-id "${NOTARIZE_KEY_ID}" --issuer "${NOTARIZE_ISSUER_ID}")
elif [[ -n "${NOTARIZE_APPLE_ID:-}" || -n "${NOTARIZE_TEAM_ID:-}" || -n "${NOTARIZE_PASSWORD:-}" ]]; then
  if [[ -z "${NOTARIZE_APPLE_ID:-}" || -z "${NOTARIZE_TEAM_ID:-}" || -z "${NOTARIZE_PASSWORD:-}" ]]; then
    echo "error: NOTARIZE_APPLE_ID, NOTARIZE_TEAM_ID, and NOTARIZE_PASSWORD must be set together." >&2
    exit 1
  fi
  if [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
    echo "error: release notarization requires NOTARIZE_PROFILE or App Store Connect API key credentials; password arguments are not allowed." >&2
    exit 1
  fi
  notarize_args=(--apple-id "${NOTARIZE_APPLE_ID}" --team-id "${NOTARIZE_TEAM_ID}" --password "${NOTARIZE_PASSWORD}")
fi

if [[ "${REQUIRE_NOTARIZATION}" == "1" && "${#notarize_args[@]}" -eq 0 ]]; then
  echo "error: notarization credentials are required when DM_LESSONMELD_REQUIRE_NOTARIZATION=1." >&2
  exit 1
fi

if [[ "${#notarize_args[@]}" -gt 0 && -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "error: notarizing the DMG requires CODESIGN_IDENTITY." >&2
  exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: app bundle not found at ${APP_DIR}; run scripts/build-app.sh release first." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

rm -rf "${STAGING_DIR}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "${CODESIGN_IDENTITY}" "${DMG_PATH}"
  codesign --verify --strict --verbose=2 "${DMG_PATH}"
fi

if [[ "${#notarize_args[@]}" -gt 0 ]]; then
  xcrun notarytool submit "${DMG_PATH}" "${notarize_args[@]}" --wait
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
fi

"${ROOT_DIR}/scripts/verify-dmg.sh" "${DMG_PATH}" >/dev/null

echo "${DMG_PATH}"
