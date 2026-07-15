#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup_script="${repo_root}/scripts/cleanup-release-signing-material.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "release signing cleanup test failed: $*" >&2
  exit 1
}

mkdir -p "${tmpdir}/bin"
ln -s "${repo_root}/scripts/fixtures/mock-security.sh" "${tmpdir}/bin/security"
security_log="${tmpdir}/security.log"
certificate_path="${tmpdir}/developer-id.p12"
keychain_path="${tmpdir}/app-signing.keychain-db"
notarization_key_path="${tmpdir}/notarization-key.p8"
original_keychains_path="${tmpdir}/original-keychains.txt"
touch "${certificate_path}" "${keychain_path}" "${notarization_key_path}"
printf '%s\n' \
  "/Users/release/Library/Keychains/login.keychain-db" \
  "/Library/Keychains/System Keychain.keychain" \
  > "${original_keychains_path}"

PATH="${tmpdir}/bin:${PATH}" MOCK_SECURITY_LOG="${security_log}" \
  "${cleanup_script}" \
  "${certificate_path}" \
  "${keychain_path}" \
  "${original_keychains_path}" \
  "${notarization_key_path}"

expected_restore=$'list-keychains\t-d\tuser\t-s\t/Users/release/Library/Keychains/login.keychain-db\t/Library/Keychains/System Keychain.keychain'
expected_delete=$'delete-keychain\t'"${keychain_path}"
[[ "$(sed -n '1p' "${security_log}")" == "${expected_restore}" ]] || fail "original keychain list was not restored first"
[[ "$(sed -n '2p' "${security_log}")" == "${expected_delete}" ]] || fail "temporary keychain was not deleted after restoration"

for path in "${certificate_path}" "${keychain_path}" "${notarization_key_path}" "${original_keychains_path}"; do
  [[ ! -e "${path}" ]] || fail "sensitive path still exists: ${path}"
done

touch "${certificate_path}" "${keychain_path}" "${notarization_key_path}"
printf '%s\n' "/Users/release/Library/Keychains/login.keychain-db" > "${original_keychains_path}"
if PATH="${tmpdir}/bin:${PATH}" \
    MOCK_SECURITY_LOG="${security_log}" \
    MOCK_SECURITY_FAIL_COMMAND="list-keychains" \
    "${cleanup_script}" \
    "${certificate_path}" \
    "${keychain_path}" \
    "${original_keychains_path}" \
    "${notarization_key_path}" \
    2>"${tmpdir}/restore-failure.stderr"; then
  fail "cleanup unexpectedly succeeded when keychain restoration failed"
fi
grep -Fq "failed to restore the original user keychain list" "${tmpdir}/restore-failure.stderr" \
  || fail "cleanup did not report the keychain restoration failure"
for path in "${certificate_path}" "${keychain_path}" "${notarization_key_path}" "${original_keychains_path}"; do
  [[ ! -e "${path}" ]] || fail "failed restoration left sensitive path behind: ${path}"
done

PATH="${tmpdir}/bin:${PATH}" MOCK_SECURITY_LOG="${security_log}" \
  "${cleanup_script}" "" "" "" ""

echo "Release signing cleanup tests passed."
