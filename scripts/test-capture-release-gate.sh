#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="${ROOT_DIR}/scripts/verify-capture-release-gate.sh"
TMPDIR_PATH="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_PATH}"' EXIT

REVISION="0123456789abcdef0123456789abcdef01234567"
REPOSITORY="BradGroux/dm-lessonmeld"
RUN_ID="123456789"
CAPTURE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MEDIA_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fail() {
  echo "capture release gate test failed: $*" >&2
  exit 1
}

write_report() {
  local path="$1"
  local revision="${2:-${REVISION}}"
  local repository="${3:-${REPOSITORY}}"
  local run_id="${4:-${RUN_ID}}"
  local capture_status="${5:-passed}"
  local capture_sha="${6:-${CAPTURE_SHA}}"

  cat >"${path}" <<JSON
{
  "schema": "io.digitalmeld.dm-lessonmeld.capture-release-gate.v1",
  "repository": "${repository}",
  "revision": "${revision}",
  "workflowRunId": "${run_id}",
  "recordedAt": "2026-07-15T03:30:00Z",
  "actor": "release-operator",
  "results": {
    "captureDeviceMatrix": {
      "status": "${capture_status}",
      "summarySha256": "${capture_sha}"
    },
    "realMediaFixture": {
      "status": "passed",
      "summarySha256": "${MEDIA_SHA}"
    },
    "manualChecks": {
      "status": "passed",
      "notes": "Window mode, revoked permissions, missing devices, and stop timing passed."
    }
  }
}
JSON
}

expect_success() {
  local description="$1"
  shift
  if ! "$@" >"${TMPDIR_PATH}/success.stdout" 2>"${TMPDIR_PATH}/success.stderr"; then
    cat "${TMPDIR_PATH}/success.stderr" >&2
    fail "${description}: command unexpectedly failed"
  fi
}

expect_failure() {
  local description="$1"
  local expected="$2"
  shift 2
  if "$@" >"${TMPDIR_PATH}/failure.stdout" 2>"${TMPDIR_PATH}/failure.stderr"; then
    fail "${description}: command unexpectedly succeeded"
  fi
  if ! grep -Fq "${expected}" "${TMPDIR_PATH}/failure.stderr"; then
    cat "${TMPDIR_PATH}/failure.stderr" >&2
    fail "${description}: expected error containing '${expected}'"
  fi
}

report="${TMPDIR_PATH}/gate.json"
write_report "${report}"
expect_success "valid tracked gate" "${VERIFIER}" "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}"

write_report "${report}" "1111111111111111111111111111111111111111"
expect_failure "wrong revision" "revision does not match release commit" \
  "${VERIFIER}" "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}"

write_report "${report}" "${REVISION}" "AnotherOrg/another-repo"
expect_failure "wrong repository" "repository does not match release repository" \
  "${VERIFIER}" "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}"

write_report "${report}" "${REVISION}" "${REPOSITORY}" "999"
expect_failure "wrong workflow run" "workflow run ID does not match downloaded artifact" \
  "${VERIFIER}" "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}"

write_report "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}" failed
expect_failure "failed capture matrix" "captureDeviceMatrix status must be passed" \
  "${VERIFIER}" "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}"

write_report "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}" passed invalid
expect_failure "invalid summary digest" "captureDeviceMatrix summary SHA-256 is invalid" \
  "${VERIFIER}" "${report}" "${REVISION}" "${REPOSITORY}" "${RUN_ID}"

echo "Capture release gate tests passed."
