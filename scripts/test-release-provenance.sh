#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-release-provenance.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

git_env=(
  GIT_AUTHOR_NAME="Release Test"
  GIT_AUTHOR_EMAIL="release-test@example.invalid"
  GIT_COMMITTER_NAME="Release Test"
  GIT_COMMITTER_EMAIL="release-test@example.invalid"
)

fail() {
  echo "release provenance test failed: $*" >&2
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

remote="${tmpdir}/remote.git"
work="${tmpdir}/work"
git init --bare --initial-branch=main "${remote}" >/dev/null
git clone "${remote}" "${work}" >/dev/null 2>&1

(
  cd "${work}"
  mkdir -p Packaging
  python3 - <<'PY'
import plistlib
from pathlib import Path

with Path("Packaging/Info.plist").open("wb") as output:
    plistlib.dump(
        {
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
        },
        output,
    )
PY
  env "${git_env[@]}" git add Packaging/Info.plist
  env "${git_env[@]}" git commit -m "Reviewed release" >/dev/null
  git push origin main >/dev/null 2>&1
)

reviewed_sha="$(git -C "${work}" rev-parse HEAD)"
(
  cd "${work}"
  git tag v1.2.3 "${reviewed_sha}"
  "${verifier}" "${reviewed_sha}" main v1.2.3 Packaging/Info.plist
  git tag v1.2.3-preview.1 "${reviewed_sha}"
  "${verifier}" "${reviewed_sha}" main v1.2.3-preview.1 Packaging/Info.plist unsigned-preview
)

expect_failure "unsigned normal tag" "unsigned-preview tag must match v1.2.3-preview.N" \
  bash -c 'cd "$1" && "$2" "$3" main v1.2.3 Packaging/Info.plist unsigned-preview' \
  _ "${work}" "${verifier}" "${reviewed_sha}"
expect_failure "signed preview tag" "signed release tag must be v1.2.3" \
  bash -c 'cd "$1" && "$2" "$3" main v1.2.3-preview.1 Packaging/Info.plist signed' \
  _ "${work}" "${verifier}" "${reviewed_sha}"

git -C "${work}" tag v9.9.9 "${reviewed_sha}"
expect_failure "version mismatch" "signed release tag must be v1.2.3" \
  bash -c 'cd "$1" && "$2" "$3" main v9.9.9 Packaging/Info.plist' \
  _ "${work}" "${verifier}" "${reviewed_sha}"

(
  cd "${work}"
  git switch -c unreviewed >/dev/null 2>&1
  printf 'unreviewed\n' > unreviewed.txt
  env "${git_env[@]}" git add unreviewed.txt
  env "${git_env[@]}" git commit -m "Unreviewed release" >/dev/null
)
unreviewed_sha="$(git -C "${work}" rev-parse HEAD)"
git -C "${work}" tag v1.2.4 "${unreviewed_sha}"

expect_failure "commit outside default branch" "not reachable from origin/main" \
  bash -c 'cd "$1" && "$2" "$3" main v1.2.4 Packaging/Info.plist' \
  _ "${work}" "${verifier}" "${unreviewed_sha}"

(
  cd "${work}"
  git switch main >/dev/null 2>&1
  git pull --ff-only origin main >/dev/null 2>&1
  python3 - <<'PY'
import plistlib
from pathlib import Path

path = Path("Packaging/Info.plist")
with path.open("rb") as source:
    data = plistlib.load(source)
data["CFBundleShortVersionString"] = "1.2.5"
data["CFBundleVersion"] = "not-a-build"
with path.open("wb") as output:
    plistlib.dump(data, output)
PY
  env "${git_env[@]}" git add Packaging/Info.plist
  env "${git_env[@]}" git commit -m "Invalid build metadata" >/dev/null
  git push origin main >/dev/null 2>&1
)
invalid_build_sha="$(git -C "${work}" rev-parse HEAD)"
git -C "${work}" tag v1.2.5 "${invalid_build_sha}"

expect_failure "invalid build metadata" "bundle build metadata is invalid" \
  bash -c 'cd "$1" && "$2" "$3" main v1.2.5 Packaging/Info.plist' \
  _ "${work}" "${verifier}" "${invalid_build_sha}"

echo "Release provenance tests passed."
