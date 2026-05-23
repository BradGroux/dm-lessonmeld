#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_PATH="${ROOT_DIR}/Casks/dm-lessonmeld.rb"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/Packaging/Info.plist")"
ZIP_PATH="${1:-}"

if [[ ! -f "${CASK_PATH}" ]]; then
  echo "error: cask not found: ${CASK_PATH}" >&2
  exit 1
fi

cask_version="$(ruby -e 'text = File.read(ARGV.fetch(0)); match = text.match(/^\s*version "([^"]+)"/); abort("missing cask version") unless match; puts match[1]' "${CASK_PATH}")"
cask_sha="$(ruby -e 'text = File.read(ARGV.fetch(0)); match = text.match(/^\s*sha256 "([^"]+)"/); abort("missing cask sha256") unless match; puts match[1]' "${CASK_PATH}")"

if [[ "${cask_version}" != "${VERSION}" ]]; then
  echo "error: cask version ${cask_version} does not match Info.plist version ${VERSION}" >&2
  exit 1
fi

if [[ -z "${ZIP_PATH}" ]]; then
  exit 0
fi

expected_zip_name="dm-lessonmeld-${VERSION}-macos.zip"
if [[ "$(basename "${ZIP_PATH}")" != "${expected_zip_name}" ]]; then
  echo "error: zip artifact $(basename "${ZIP_PATH}") does not match expected ${expected_zip_name}" >&2
  exit 1
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "error: zip artifact not found: ${ZIP_PATH}" >&2
  exit 1
fi

computed_sha="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
if [[ "${computed_sha}" != "${cask_sha}" ]]; then
  echo "error: cask sha256 ${cask_sha} does not match ${ZIP_PATH} sha256 ${computed_sha}" >&2
  exit 1
fi
