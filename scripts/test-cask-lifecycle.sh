#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

if ! command -v brew >/dev/null 2>&1; then
  echo "warning: Homebrew is unavailable; skipping cask lifecycle evaluation." >&2
  exit 0
fi

artifacts="$(brew ruby -e '
  require "cask/cask_loader"
  cask = Cask::CaskLoader.load(File.read(ARGV.fetch(0)))
  puts cask.artifacts_list
' Casks/dm-lessonmeld.rb)"

required_entries=(
  'quit: "io.digitalmeld.dm-lessonmeld"'
  '~/Library/Application Support/DMLessonMeld'
  '~/Library/Caches/io.digitalmeld.dm-lessonmeld'
  '~/Library/Preferences/io.digitalmeld.dm-lessonmeld.plist'
  '~/Library/Saved Application State/io.digitalmeld.dm-lessonmeld.savedState'
)

for required_entry in "${required_entries[@]}"; do
  if ! grep -Fq "${required_entry}" <<<"${artifacts}"; then
    echo "error: cask lifecycle is missing ${required_entry}" >&2
    exit 1
  fi
done

if grep -Fq '.dmlm' <<<"${artifacts}"; then
  echo "error: cask cleanup must not target user lesson projects." >&2
  exit 1
fi

echo "Cask lifecycle checks passed."
