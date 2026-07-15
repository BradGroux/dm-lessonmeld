#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_workflow="${repo_root}/.github/workflows/release.yml"
publish_workflow="${repo_root}/.github/workflows/publish-release.yml"
capture_gate_workflow="${repo_root}/.github/workflows/capture-release-gate.yml"

fail() {
  echo "release workflow gate test failed: $*" >&2
  exit 1
}

grep -Fq "gh release create" "${stage_workflow}" || fail "tag workflow does not create a staged release"
grep -Fq "verify-capture-gate:" "${stage_workflow}" || fail "tag workflow does not verify tracked capture evidence"
grep -Fq "needs: [verify-release-provenance, verify-capture-gate]" "${stage_workflow}" || fail "release build can bypass the capture gate"
grep -Fq "scripts/verify-capture-release-gate.sh" "${stage_workflow}" || fail "tag workflow does not validate capture gate artifacts"
grep -Fq -- '--branch "${DEFAULT_BRANCH}"' "${stage_workflow}" || fail "tag workflow can use capture gates from non-default branches"
grep -Fq -- "--draft" "${stage_workflow}" || fail "tag workflow release is not a draft"
grep -Fq -- "--latest=false" "${stage_workflow}" || fail "staged release can become latest"
if grep -Fq -- "--draft=false" "${stage_workflow}"; then
  fail "tag workflow can publish its own staged release"
fi

grep -Fq "workflow_dispatch:" "${publish_workflow}" || fail "publish workflow is not manually dispatched"
grep -Fq "capture_gate_run_id:" "${publish_workflow}" || fail "publish workflow does not require a capture gate run"
grep -Fq "gh run download" "${publish_workflow}" || fail "publish workflow does not download capture gate evidence"
grep -Fq "scripts/verify-capture-release-gate.sh" "${publish_workflow}" || fail "publish workflow does not verify capture gate evidence"
grep -Fq '.headBranch' "${publish_workflow}" || fail "publish workflow does not verify the capture gate branch"
grep -Fq "brew style Casks/dm-lessonmeld.rb" "${publish_workflow}" || fail "publish workflow does not run brew style"
grep -Fq "scripts/verify-cask-release.sh" "${publish_workflow}" || fail "publish workflow does not verify the cask"
grep -Fq -- "--draft=false" "${publish_workflow}" || fail "publish workflow never clears the draft flag"
grep -Fq -- "--latest=false" "${publish_workflow}" || fail "preview publication does not disable latest"

cask_line="$(grep -n -F "scripts/verify-cask-release.sh" "${publish_workflow}" | head -1 | cut -d: -f1)"
capture_gate_line="$(grep -n -F "scripts/verify-capture-release-gate.sh" "${publish_workflow}" | head -1 | cut -d: -f1)"
publish_line="$(grep -n -F "gh release edit" "${publish_workflow}" | head -1 | cut -d: -f1)"
[[ "${cask_line}" -lt "${publish_line}" ]] || fail "release can publish before cask verification"
[[ "${capture_gate_line}" -lt "${publish_line}" ]] || fail "release can publish before capture gate verification"

grep -Fq "workflow_dispatch:" "${capture_gate_workflow}" || fail "capture gate workflow is not manually dispatched"
grep -Fq 'refs/heads/${DEFAULT_BRANCH}' "${capture_gate_workflow}" || fail "capture gate can run from a non-default branch"
grep -Fq "capture_summary_sha256:" "${capture_gate_workflow}" || fail "capture gate does not record capture summary fingerprints"
grep -Fq "real_media_summary_sha256:" "${capture_gate_workflow}" || fail "capture gate does not record real-media summary fingerprints"
grep -Fq "actions/upload-artifact" "${capture_gate_workflow}" || fail "capture gate does not retain an evidence artifact"

echo "Release workflow gate tests passed."
