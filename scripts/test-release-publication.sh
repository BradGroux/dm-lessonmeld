#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-release-publication.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "release publication test failed: $*" >&2
  exit 1
}

expect_success() {
  local description="$1"
  shift
  if ! "$@" >"${tmpdir}/success.stdout" 2>"${tmpdir}/success.stderr"; then
    cat "${tmpdir}/success.stderr" >&2
    fail "${description}: command unexpectedly failed"
  fi
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

expect_success "signed public release" "${verifier}" signed v1.2.3 1.2.3
grep -Fxq "mode=signed" "${tmpdir}/success.stdout" || fail "signed mode output is missing"
grep -Fxq "prerelease=0" "${tmpdir}/success.stdout" || fail "signed prerelease output is missing"
grep -Fxq "latest=1" "${tmpdir}/success.stdout" || fail "signed latest output is missing"

expect_success "unsigned developer preview" "${verifier}" unsigned-preview v1.2.3-preview.1 1.2.3
grep -Fxq "mode=unsigned-preview" "${tmpdir}/success.stdout" || fail "preview mode output is missing"
grep -Fxq "prerelease=1" "${tmpdir}/success.stdout" || fail "preview prerelease output is missing"
grep -Fxq "latest=0" "${tmpdir}/success.stdout" || fail "preview latest output is missing"

expect_failure "unsigned normal tag" "unsigned-preview tag must match v1.2.3-preview.N" \
  "${verifier}" unsigned-preview v1.2.3 1.2.3
expect_failure "malformed preview tag" "unsigned-preview tag must match v1.2.3-preview.N" \
  "${verifier}" unsigned-preview v1.2.3-preview.latest 1.2.3
expect_failure "zero preview number" "unsigned-preview tag must match v1.2.3-preview.N" \
  "${verifier}" unsigned-preview v1.2.3-preview.0 1.2.3
expect_failure "signed preview tag" "signed release tag must be v1.2.3" \
  "${verifier}" signed v1.2.3-preview.1 1.2.3
expect_failure "unsupported release mode" "release mode must be signed or unsigned-preview" \
  "${verifier}" nightly v1.2.3 1.2.3

echo "Release publication tests passed."
