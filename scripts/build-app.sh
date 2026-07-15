#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
PRODUCT_NAME="DMLessonMeld"
CLI_PRODUCT_NAME="dmlesson"
APP_NAME="Digital Meld LessonMeld"
APP_DIR="${ROOT_DIR}/Packaging/${APP_NAME}.app"
ENTITLEMENTS_PATH="${ROOT_DIR}/Packaging/Entitlements.plist"

cd "${ROOT_DIR}"

swift build --configuration "${CONFIGURATION}" --product "${PRODUCT_NAME}"
swift build --configuration "${CONFIGURATION}" --product "${CLI_PRODUCT_NAME}"

BIN_DIR="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/${PRODUCT_NAME}"
CLI_EXECUTABLE_PATH="${BIN_DIR}/${CLI_PRODUCT_NAME}"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "error: executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

if [[ ! -x "${CLI_EXECUTABLE_PATH}" ]]; then
  echo "error: CLI executable not found at ${CLI_EXECUTABLE_PATH}" >&2
  exit 1
fi

plutil -lint Packaging/Info.plist >/dev/null
plutil -lint Packaging/Entitlements.plist >/dev/null

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources/bin"

cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"
cp "${CLI_EXECUTABLE_PATH}" "${APP_DIR}/Contents/Resources/bin/${CLI_PRODUCT_NAME}"
cp "Packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
chmod +x "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"
chmod +x "${APP_DIR}/Contents/Resources/bin/${CLI_PRODUCT_NAME}"

if [[ -f "Packaging/AppIcon.icns" ]]; then
  cp "Packaging/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

if [[ "${DM_LESSONMELD_SKIP_ADHOC_SIGN:-0}" != "1" ]]; then
  codesign --force --deep --entitlements "${ENTITLEMENTS_PATH}" --sign - "${APP_DIR}" >/dev/null
fi

echo "${APP_DIR}"
