#!/usr/bin/env bash
set -euo pipefail

release_mode="$(printf '%s' "${1:-signed}" | tr '[:upper:]' '[:lower:]')"
tag_name="${2:-}"
version="${3:-}"

fail() {
  echo "release publication verification failed: $*" >&2
  exit 1
}

[[ -n "${tag_name}" ]] || fail "tag name is required"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release version is invalid"

case "${release_mode}" in
  signed)
    expected_tag="v${version}"
    [[ "${tag_name}" == "${expected_tag}" ]] \
      || fail "signed release tag must be ${expected_tag}"
    prerelease=0
    latest=1
    ;;
  unsigned-preview)
    preview_pattern="^v${version//./\\.}-preview\\.[1-9][0-9]*$"
    [[ "${tag_name}" =~ ${preview_pattern} ]] \
      || fail "unsigned-preview tag must match v${version}-preview.N with N greater than zero"
    prerelease=1
    latest=0
    ;;
  *)
    fail "release mode must be signed or unsigned-preview"
    ;;
esac

echo "mode=${release_mode}"
echo "prerelease=${prerelease}"
echo "latest=${latest}"
