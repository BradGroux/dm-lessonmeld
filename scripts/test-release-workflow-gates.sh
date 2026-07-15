#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_workflow="${repo_root}/.github/workflows/release.yml"
publish_workflow="${repo_root}/.github/workflows/publish-release.yml"

fail() {
  echo "release workflow gate test failed: $*" >&2
  exit 1
}

grep -Fq "gh release create" "${stage_workflow}" || fail "tag workflow does not create a staged release"
grep -Fq -- "--draft" "${stage_workflow}" || fail "tag workflow release is not a draft"
grep -Fq -- "--latest=false" "${stage_workflow}" || fail "staged release can become latest"
if grep -Fq -- "--draft=false" "${stage_workflow}"; then
  fail "tag workflow can publish its own staged release"
fi

grep -Fq "workflow_dispatch:" "${publish_workflow}" || fail "publish workflow is not manually dispatched"
grep -Fq "brew style Casks/dm-lessonmeld.rb" "${publish_workflow}" || fail "publish workflow does not run brew style"
grep -Fq "scripts/verify-cask-release.sh" "${publish_workflow}" || fail "publish workflow does not verify the cask"
grep -Fq -- "--draft=false" "${publish_workflow}" || fail "publish workflow never clears the draft flag"
grep -Fq -- "--latest=false" "${publish_workflow}" || fail "preview publication does not disable latest"

cask_line="$(grep -n -F "scripts/verify-cask-release.sh" "${publish_workflow}" | head -1 | cut -d: -f1)"
publish_line="$(grep -n -F "gh release edit" "${publish_workflow}" | head -1 | cut -d: -f1)"
[[ "${cask_line}" -lt "${publish_line}" ]] || fail "release can publish before cask verification"

echo "Release workflow gate tests passed."
