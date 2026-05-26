#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Digital Meld LessonMeld"
APP_DIR="${ROOT_DIR}/Packaging/${APP_NAME}.app"
ENTITLEMENTS_PATH="${ROOT_DIR}/Packaging/Entitlements.plist"
DIST_DIR="${ROOT_DIR}/.build/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/Packaging/Info.plist")"
ZIP_PATH="${DIST_DIR}/dm-lessonmeld-${VERSION}-macos.zip"
DMG_PATH="${DIST_DIR}/dm-lessonmeld-${VERSION}-macos.dmg"
REQUIRE_NOTARIZATION="${DM_LESSONMELD_REQUIRE_NOTARIZATION:-0}"

cd "${ROOT_DIR}"

scripts/build-app.sh release >/dev/null
plutil -lint Packaging/Info.plist >/dev/null
plutil -lint Packaging/Entitlements.plist >/dev/null

NOTARIZE_ARGS=()
if [[ -n "${NOTARIZE_PROFILE:-}" ]]; then
  NOTARIZE_ARGS=(--keychain-profile "${NOTARIZE_PROFILE}")
elif [[ -n "${NOTARIZE_KEY_PATH:-}" || -n "${NOTARIZE_KEY_ID:-}" || -n "${NOTARIZE_ISSUER_ID:-}" ]]; then
  if [[ -z "${NOTARIZE_KEY_PATH:-}" || -z "${NOTARIZE_KEY_ID:-}" || -z "${NOTARIZE_ISSUER_ID:-}" ]]; then
    echo "error: NOTARIZE_KEY_PATH, NOTARIZE_KEY_ID, and NOTARIZE_ISSUER_ID must be set together." >&2
    exit 1
  fi

  NOTARIZE_ARGS=(--key "${NOTARIZE_KEY_PATH}" --key-id "${NOTARIZE_KEY_ID}" --issuer "${NOTARIZE_ISSUER_ID}")
elif [[ -n "${NOTARIZE_APPLE_ID:-}" || -n "${NOTARIZE_TEAM_ID:-}" || -n "${NOTARIZE_PASSWORD:-}" ]]; then
  if [[ -z "${NOTARIZE_APPLE_ID:-}" || -z "${NOTARIZE_TEAM_ID:-}" || -z "${NOTARIZE_PASSWORD:-}" ]]; then
    echo "error: NOTARIZE_APPLE_ID, NOTARIZE_TEAM_ID, and NOTARIZE_PASSWORD must be set together." >&2
    exit 1
  fi

  if [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
    echo "error: release notarization requires NOTARIZE_PROFILE or App Store Connect API key credentials; password arguments are not allowed." >&2
    exit 1
  fi

  NOTARIZE_ARGS=(--apple-id "${NOTARIZE_APPLE_ID}" --team-id "${NOTARIZE_TEAM_ID}" --password "${NOTARIZE_PASSWORD}")
fi

if [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
  if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "error: CODESIGN_IDENTITY is required when DM_LESSONMELD_REQUIRE_NOTARIZATION=1." >&2
    exit 1
  fi
  if [[ "${#NOTARIZE_ARGS[@]}" -eq 0 ]]; then
    echo "error: notarization credentials are required when DM_LESSONMELD_REQUIRE_NOTARIZATION=1." >&2
    exit 1
  fi
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS_PATH}" --timestamp --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
  codesign --verify --strict --deep --verbose=2 "${APP_DIR}"
else
  codesign --verify --strict --deep --verbose=2 "${APP_DIR}"
  echo "warning: CODESIGN_IDENTITY is not set; packaging an ad-hoc signed, non-notarized app." >&2
fi

mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}" "${DMG_PATH}"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"

if [[ "${#NOTARIZE_ARGS[@]}" -gt 0 ]]; then
  if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "error: notarization requires CODESIGN_IDENTITY." >&2
    exit 1
  fi

  xcrun notarytool submit "${ZIP_PATH}" "${NOTARIZE_ARGS[@]}" --wait
  xcrun stapler staple "${APP_DIR}"
  xcrun stapler validate "${APP_DIR}"
  rm -f "${ZIP_PATH}"
  ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
fi

scripts/package-dmg.sh >/dev/null

echo "zip_path=${ZIP_PATH}"
echo "dmg_path=${DMG_PATH}"
