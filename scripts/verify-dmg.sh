#!/usr/bin/env bash
set -euo pipefail

ATTEMPTS="${DM_LESSONMELD_DMG_VERIFY_ATTEMPTS:-5}"
DELAY_SECONDS="${DM_LESSONMELD_DMG_VERIFY_DELAY_SECONDS:-5}"

if [[ "$#" -eq 0 ]]; then
  echo "usage: scripts/verify-dmg.sh <dmg-path> [dmg-path ...]" >&2
  exit 2
fi

for dmg_path in "$@"; do
  if [[ ! -f "${dmg_path}" ]]; then
    echo "error: DMG not found: ${dmg_path}" >&2
    exit 1
  fi

  for ((attempt = 1; attempt <= ATTEMPTS; attempt += 1)); do
    if hdiutil verify "${dmg_path}"; then
      continue 2
    fi

    if [[ "${attempt}" -eq "${ATTEMPTS}" ]]; then
      echo "error: hdiutil verify failed after ${ATTEMPTS} attempts: ${dmg_path}" >&2
      exit 1
    fi

    echo "hdiutil verify failed for ${dmg_path}; retrying in ${DELAY_SECONDS}s (${attempt}/${ATTEMPTS})..." >&2
    sleep "${DELAY_SECONDS}"
  done
done
