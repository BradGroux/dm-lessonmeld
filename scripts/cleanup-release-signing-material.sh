#!/usr/bin/env bash
set -euo pipefail

certificate_path="${1:-}"
keychain_path="${2:-}"
original_keychains_path="${3:-}"
notarization_key_path="${4:-}"
cleanup_status=0

if [[ -n "${original_keychains_path}" ]]; then
  if [[ -f "${original_keychains_path}" ]]; then
    original_keychains=()
    while IFS= read -r keychain; do
      [[ -n "${keychain}" ]] && original_keychains+=("${keychain}")
    done < "${original_keychains_path}"

    if [[ "${#original_keychains[@]}" -gt 0 ]]; then
      if ! security list-keychains -d user -s "${original_keychains[@]}"; then
        echo "error: failed to restore the original user keychain list." >&2
        cleanup_status=1
      fi
    else
      echo "error: original user keychain list was empty." >&2
      cleanup_status=1
    fi
  else
    echo "error: original user keychain list is missing: ${original_keychains_path}" >&2
    cleanup_status=1
  fi
fi

if [[ -n "${keychain_path}" ]]; then
  security delete-keychain "${keychain_path}" >/dev/null 2>&1 || true
  rm -f "${keychain_path}"
fi

for sensitive_path in "${certificate_path}" "${notarization_key_path}" "${original_keychains_path}"; do
  [[ -z "${sensitive_path}" ]] || rm -f "${sensitive_path}"
done

exit "${cleanup_status}"
