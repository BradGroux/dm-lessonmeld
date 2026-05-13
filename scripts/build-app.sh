#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
PRODUCT_NAME="DMLessonMeld"
APP_NAME="Digital Meld LessonMeld"
APP_DIR="${ROOT_DIR}/Packaging/${APP_NAME}.app"

cd "${ROOT_DIR}"

swift build --configuration "${CONFIGURATION}" --product "${PRODUCT_NAME}"

BIN_DIR="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/${PRODUCT_NAME}"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "error: executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

plutil -lint Packaging/Info.plist >/dev/null

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"
cp "Packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
chmod +x "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"

if [[ -f "Packaging/AppIcon.icns" ]]; then
  cp "Packaging/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

if [[ "${DM_LESSONMELD_SKIP_ADHOC_SIGN:-0}" != "1" ]]; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
fi

echo "${APP_DIR}"
