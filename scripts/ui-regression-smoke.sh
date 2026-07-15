#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_root="${repo_root}/.build/ui-regression-artifacts"
skip_build=0
update_baselines=0

usage() {
  echo "Usage: scripts/ui-regression-smoke.sh [--skip-build] [--output directory] [--update-baselines]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      skip_build=1
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      output_root="$2"
      shift 2
      ;;
    --update-baselines)
      update_baselines=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

cd "${repo_root}"
if [[ "${skip_build}" -eq 0 ]]; then
  swift build --product DMLessonMeld
fi

bin_dir="$(swift build --show-bin-path)"
app_binary="${bin_dir}/DMLessonMeld"
if [[ ! -x "${app_binary}" ]]; then
  echo "error: built app executable not found at ${app_binary}" >&2
  exit 1
fi

mkdir -p "${output_root}"

run_app_fixture() {
  DM_LESSONMELD_ENABLE_UI_REGRESSION=1 python3 - "$@" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

try:
    completed = subprocess.run(sys.argv[1:], env=os.environ.copy(), timeout=30, check=False)
except subprocess.TimeoutExpired:
    if "--ui-regression-output" in sys.argv:
        output_index = sys.argv.index("--ui-regression-output") + 1
        if output_index < len(sys.argv):
            output = Path(sys.argv[output_index])
            output.mkdir(parents=True, exist_ok=True)
            (output / "runner-error.txt").write_text("Rendered UI fixture timed out after 30 seconds.\n")
    print("rendered UI fixture timed out after 30 seconds", file=sys.stderr)
    raise SystemExit(124)
raise SystemExit(completed.returncode)
PY
}

scenarios=(
  "video-editor-overlays:light"
  "video-editor-overlays:dark"
  "video-editor-captions:light"
  "video-editor-captions:dark"
  "video-editor-narrow:dark"
  "annotation-toolbar:dark"
)

failures=0
for scenario_appearance in "${scenarios[@]}"; do
  fixture="${scenario_appearance%%:*}"
  appearance="${scenario_appearance##*:}"
  artifact_dir="${output_root}/${fixture}-${appearance}"
  rm -rf "${artifact_dir}"
  mkdir -p "${artifact_dir}"

  echo "Rendered UI: ${fixture} (${appearance})"
  if ! run_app_fixture "${app_binary}" \
      --ui-regression-fixture "${fixture}" \
      --ui-regression-output "${artifact_dir}" \
      --ui-regression-appearance "${appearance}"; then
    echo "FAIL: ${fixture} (${appearance}); artifacts: ${artifact_dir}" >&2
    failures=$((failures + 1))
    continue
  fi

  baseline="${repo_root}/Tests/UIRegressionBaselines/${fixture}-${appearance}.json"
  if [[ "${fixture}" == "video-editor-overlays" ]]; then
    baseline_args=("${artifact_dir}/report.json" "${baseline}")
    if [[ "${update_baselines}" -eq 1 ]]; then
      baseline_args+=("--update")
    fi
    if ! python3 scripts/verify-ui-regression-baseline.py "${baseline_args[@]}"; then
      echo "FAIL: screenshot baseline ${fixture} (${appearance}); artifacts: ${artifact_dir}" >&2
      failures=$((failures + 1))
      continue
    fi
  fi
  echo "PASS: ${fixture} (${appearance})"
done

if [[ "${failures}" -ne 0 ]]; then
  echo "Rendered UI regression failed: ${failures} scenario(s). Artifacts: ${output_root}" >&2
  exit 1
fi

echo "Rendered UI regression passed: ${#scenarios[@]} scenarios. Artifacts: ${output_root}"
