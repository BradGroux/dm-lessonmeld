#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-cask-release.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "cask release test failed: $*" >&2
  exit 1
}

expect_failure() {
  local description="$1"
  local expected="$2"
  shift 2
  if "$@" >"${tmpdir}/failure.stdout" 2>"${tmpdir}/failure.stderr"; then
    fail "${description}: command unexpectedly succeeded"
  fi
  if ! grep -Fq "${expected}" "${tmpdir}/failure.stderr"; then
    cat "${tmpdir}/failure.stderr" >&2
    fail "${description}: expected error containing '${expected}'"
  fi
}

version="1.2.3"
zip_path="${tmpdir}/dm-lessonmeld-${version}-macos.zip"
cask_path="${tmpdir}/dm-lessonmeld.rb"
info_plist="${tmpdir}/Info.plist"
printf 'reviewed release artifact\n' > "${zip_path}"
zip_sha="$(shasum -a 256 "${zip_path}" | awk '{print $1}')"

python3 - "${info_plist}" "${version}" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as output:
    plistlib.dump({"CFBundleShortVersionString": sys.argv[2]}, output)
PY

write_cask() {
  local cask_version="$1"
  local cask_sha="$2"
  printf 'cask "dm-lessonmeld" do\n  version "%s"\n  sha256 "%s"\nend\n' \
    "${cask_version}" "${cask_sha}" > "${cask_path}"
}

write_cask "${version}" "${zip_sha}"
"${verifier}" "${zip_path}" "${cask_path}" "${info_plist}"

write_cask "9.9.9" "${zip_sha}"
expect_failure "version mismatch" "does not match release version ${version}" \
  "${verifier}" "${zip_path}" "${cask_path}" "${info_plist}"

write_cask "${version}" "$(printf '0%.0s' {1..64})"
expect_failure "SHA mismatch" "does not match" \
  "${verifier}" "${zip_path}" "${cask_path}" "${info_plist}"

write_cask "${version}" "${zip_sha}"
wrong_name="${tmpdir}/unexpected.zip"
cp "${zip_path}" "${wrong_name}"
expect_failure "artifact name mismatch" "does not match expected dm-lessonmeld-${version}-macos.zip" \
  "${verifier}" "${wrong_name}" "${cask_path}" "${info_plist}"

echo "Cask release tests passed."
