#!/usr/bin/env bash
set -euo pipefail

tagged_revision="${1:-}"
default_branch="${2:-}"
tag_name="${3:-}"
info_plist="${4:-Packaging/Info.plist}"
release_mode="${5:-signed}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "release provenance verification failed: $*" >&2
  exit 1
}

[[ -n "${tagged_revision}" ]] || fail "tagged revision is required"
[[ -n "${default_branch}" ]] || fail "default branch is required"
[[ -n "${tag_name}" ]] || fail "tag name is required"
git check-ref-format --branch "${default_branch}" >/dev/null 2>&1 \
  || fail "default branch name is invalid"
tag_ref="refs/tags/${tag_name}"
git check-ref-format "${tag_ref}" >/dev/null 2>&1 \
  || fail "tag name is invalid"

tagged_commit="$(git rev-parse --verify "${tagged_revision}^{commit}" 2>/dev/null)" \
  || fail "tagged revision does not resolve to a commit"
tag_commit="$(git rev-parse --verify "${tag_ref}^{commit}" 2>/dev/null)" \
  || fail "tag does not resolve to a commit"
[[ "${tag_commit}" == "${tagged_commit}" ]] \
  || fail "tag does not resolve to the supplied revision"
default_ref="refs/remotes/origin/${default_branch}"
git show-ref --verify --quiet "${default_ref}" \
  || fail "origin/${default_branch} is unavailable; fetch the default branch before verification"

git merge-base --is-ancestor "${tagged_commit}" "${default_ref}" \
  || fail "tagged commit is not reachable from origin/${default_branch}"

metadata_output="$(python3 - "${tagged_commit}" "${info_plist}" <<'PY'
import plistlib
import re
import subprocess
import sys

commit, plist_path = sys.argv[1:]

try:
    payload = subprocess.check_output(
        ["git", "show", f"{commit}:{plist_path}"],
        stderr=subprocess.PIPE,
    )
    metadata = plistlib.loads(payload)
except (subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
    print(
        f"release provenance verification failed: cannot read {plist_path} from tagged commit",
        file=sys.stderr,
    )
    raise SystemExit(1) from error

version = metadata.get("CFBundleShortVersionString")
build = metadata.get("CFBundleVersion")
if not isinstance(version, str) or not version:
    print("release provenance verification failed: bundle version is missing", file=sys.stderr)
    raise SystemExit(1)
if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is None:
    print("release provenance verification failed: bundle version is invalid", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(build, str) or re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", build) is None:
    print("release provenance verification failed: bundle build metadata is invalid", file=sys.stderr)
    raise SystemExit(1)

print(f"version={version}")
print(f"build={build}")
PY
)"
printf '%s\n' "${metadata_output}"
version="$(printf '%s\n' "${metadata_output}" | awk -F= '/^version=/{print $2}')"
"${script_dir}/verify-release-publication.sh" "${release_mode}" "${tag_name}" "${version}"
