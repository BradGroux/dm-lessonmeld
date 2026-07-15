#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Digital Meld LessonMeld"
APP_DIR="${ROOT_DIR}/Packaging/${APP_NAME}.app"
BUNDLED_CLI="${APP_DIR}/Contents/Resources/bin/dmlesson"
SKIP_BUILD=0

if [[ "${1:-}" == "--skip-build" ]]; then
  SKIP_BUILD=1
elif [[ "${#}" -ne 0 ]]; then
  echo "usage: scripts/test-cli-packaging.sh [--skip-build]" >&2
  exit 2
fi

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  scripts/build-app.sh release >/dev/null
fi

if [[ ! -x "${BUNDLED_CLI}" ]]; then
  echo "error: packaged CLI is missing or not executable at ${BUNDLED_CLI}" >&2
  exit 1
fi

"${BUNDLED_CLI}" --help | grep -q '^dmlesson$'

if ! command -v brew >/dev/null 2>&1; then
  echo "warning: Homebrew is unavailable; skipping cask artifact evaluation." >&2
  exit 0
fi

temporary_cask="$(mktemp)"
trap 'rm -f "${temporary_cask}"' EXIT

cask_artifacts() {
  brew ruby -e '
    require "cask/cask_loader"
    cask = Cask::CaskLoader.load(File.read(ARGV.fetch(0)))
    puts cask.artifacts_list
  ' "${1}"
}

current_artifacts="$(cask_artifacts Casks/dm-lessonmeld.rb)"
if grep -q 'dmlesson' <<<"${current_artifacts}"; then
  echo "error: the v0.0.12 cask must not expose a CLI absent from its archive." >&2
  exit 1
fi

sed 's/version "0\.0\.12"/version "0.0.13"/' Casks/dm-lessonmeld.rb > "${temporary_cask}"
future_artifacts="$(cask_artifacts "${temporary_cask}")"
if ! grep -q 'Contents/Resources/bin/dmlesson' <<<"${future_artifacts}"; then
  echo "error: cask versions with packaged CLI support must expose dmlesson." >&2
  exit 1
fi

echo "CLI packaging checks passed."
