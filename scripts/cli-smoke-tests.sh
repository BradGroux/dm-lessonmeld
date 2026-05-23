#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/cli-smoke-tests.sh [--skip-build] [--output directory] [--keep-output]

Builds and exercises the dmlesson CLI against safe, non-capturing workflows:
help, permissions status, window listing, settings JSON, project
creation/inspection, edit and render planning, packaging, config backup
planning, app status, usage failures, and README/docs CLI example drift.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_bin="${SWIFT:-swift}"
python_bin="${PYTHON:-python3}"
build_cli=1
keep_output=0
output_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      build_cli=0
      shift
      ;;
    --output)
      output_root="${2:-}"
      shift 2
      ;;
    --keep-output)
      keep_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v "$python_bin" >/dev/null 2>&1; then
  echo "Missing Python runtime: $python_bin" >&2
  exit 2
fi

if [[ -z "$output_root" ]]; then
  output_root="$(mktemp -d "${TMPDIR:-/tmp}/dm-lessonmeld-cli-smoke.XXXXXX")"
else
  mkdir -p "$output_root"
fi

logs_dir="$output_root/logs"
work_dir="$output_root/work"
summary_file="$output_root/summary.tsv"
cli_path="$repo_root/.build/debug/dmlesson"
pass_count=0
fail_count=0

mkdir -p "$logs_dir" "$work_dir"
printf "status\tcheck\tdetail\n" > "$summary_file"

cleanup() {
  if [[ "$keep_output" -eq 0 ]]; then
    rm -rf "$output_root"
  fi
}
trap cleanup EXIT

record_status() {
  local status="$1"
  local name="$2"
  local detail="$3"
  printf "%s\t%s\t%s\n" "$status" "$name" "$detail" >> "$summary_file"
  printf "[%s] %s - %s\n" "$status" "$name" "$detail"
  case "$status" in
    PASS) pass_count=$((pass_count + 1)) ;;
    FAIL) fail_count=$((fail_count + 1)) ;;
  esac
}

safe_log_name() {
  printf "%s" "$1" | tr ' /' '__' | tr -cd '[:alnum:]_.-'
}

run_step() {
  local name="$1"
  shift
  local log_name stdout_log stderr_log
  log_name="$(safe_log_name "$name")"
  stdout_log="$logs_dir/${log_name}.stdout.log"
  stderr_log="$logs_dir/${log_name}.stderr.log"

  if "$@" >"$stdout_log" 2>"$stderr_log"; then
    record_status "PASS" "$name" "stdout: $stdout_log"
    return 0
  fi

  record_status "FAIL" "$name" "stderr: $stderr_log"
  return 1
}

validate_json_shape() {
  local name="$1"
  local json_path="$2"
  shift 2

  "$python_bin" - "$json_path" "$@" <<'PY'
import json
import sys

json_path = sys.argv[1]
specs = sys.argv[2:]

with open(json_path, "r", encoding="utf-8") as handle:
    value = json.load(handle)

def resolve(root, path):
    if path == "@":
        return root
    current = root
    for part in path.split("."):
        if isinstance(current, dict):
            if part not in current:
                raise AssertionError(f"missing key: {path}")
            current = current[part]
        elif isinstance(current, list) and part.isdigit():
            index = int(part)
            try:
                current = current[index]
            except IndexError as error:
                raise AssertionError(f"missing list index: {path}") from error
        else:
            raise AssertionError(f"cannot resolve {path} through {type(current).__name__}")
    return current

def matches_type(actual, expected):
    if expected == "present":
        return True
    if expected == "dict":
        return isinstance(actual, dict)
    if expected == "list":
        return isinstance(actual, list)
    if expected == "nonempty-list":
        return isinstance(actual, list) and len(actual) > 0
    if expected == "str":
        return isinstance(actual, str)
    if expected == "bool":
        return isinstance(actual, bool)
    if expected == "int":
        return isinstance(actual, int) and not isinstance(actual, bool)
    if expected == "number":
        return isinstance(actual, (int, float)) and not isinstance(actual, bool)
    if expected == "null-or-str":
        return actual is None or isinstance(actual, str)
    raise AssertionError(f"unknown expected type: {expected}")

for spec in specs:
    try:
        path, expected_type = spec.split("=", 1)
    except ValueError as error:
        raise AssertionError(f"invalid shape spec: {spec}") from error
    actual = resolve(value, path)
    if not matches_type(actual, expected_type):
        raise AssertionError(
            f"{path} expected {expected_type}, got {type(actual).__name__}: {actual!r}"
        )
PY
  record_status "PASS" "$name JSON shape" "$json_path"
}

run_json() {
  local name="$1"
  local output_name="$2"
  shift 2
  local specs=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    specs+=("$1")
    shift
  done
  if [[ "$#" -eq 0 ]]; then
    echo "run_json missing command separator for $name" >&2
    exit 2
  fi
  shift

  local stdout_path="$logs_dir/${output_name}.json"
  local stderr_path="$logs_dir/${output_name}.stderr.log"
  if "$@" >"$stdout_path" 2>"$stderr_path"; then
    record_status "PASS" "$name" "json: $stdout_path"
    validate_json_shape "$name" "$stdout_path" "${specs[@]}"
    return 0
  fi

  record_status "FAIL" "$name" "stderr: $stderr_path"
  return 1
}

validate_window_titles_redacted() {
  local name="$1"
  local json_path="$2"

  "$python_bin" - "$json_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    windows = json.load(handle)

for index, window in enumerate(windows):
    if window.get("title") != "Window title redacted":
        raise AssertionError(f"window {index} title was not redacted")
PY
  record_status "PASS" "$name" "$json_path"
}

run_expected_failure() {
  local name="$1"
  local expected_stderr="$2"
  shift 2
  local log_name stdout_log stderr_log status
  log_name="$(safe_log_name "$name")"
  stdout_log="$logs_dir/${log_name}.stdout.log"
  stderr_log="$logs_dir/${log_name}.stderr.log"

  set +e
  "$@" >"$stdout_log" 2>"$stderr_log"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]] && grep -Fq -- "$expected_stderr" "$stderr_log"; then
    record_status "PASS" "$name" "expected failure: $stderr_log"
    return 0
  fi

  record_status "FAIL" "$name" "unexpected exit $status: $stderr_log"
  return 1
}

check_documented_commands() {
  local actual="$work_dir/documented-commands.actual"
  local expected="$work_dir/documented-commands.expected"
  local diff_log="$logs_dir/documented-commands.diff"

  "$python_bin" - "$repo_root/README.md" "$repo_root/docs/USAGE.md" >"$actual" <<'PY'
import re
import sys

commands = set()
for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("swift run dmlesson "):
                commands.add(re.sub(r"\s+", " ", stripped))

for command in sorted(commands):
    print(command)
PY

  cat >"$expected" <<'EXPECTED'
swift run dmlesson --help
swift run dmlesson app status --json
swift run dmlesson config plan ~/.dm-lessonmeld --json
swift run dmlesson edit validate /tmp/Intro.dmlm --json
swift run dmlesson agent workflows --target codex --json
swift run dmlesson learnhouse package /tmp/Intro.dmlm --output /tmp/lesson-export --archive
swift run dmlesson connectors common-cartridge package /tmp/Intro.dmlm --output /tmp/connectors --json
swift run dmlesson connectors scorm package /tmp/Intro.dmlm --output /tmp/connectors --json
swift run dmlesson connectors video-host handoff /tmp/Intro.dmlm --output /tmp/connectors --json
swift run dmlesson connectors xapi package /tmp/Intro.dmlm --output /tmp/connectors --json
swift run dmlesson permissions status --json
swift run dmlesson presets apply /tmp/Intro.dmlm --preset /tmp/workshop.dmlpreset
swift run dmlesson presets apply /tmp/Other.dmlm --preset /tmp/workshop.dmlpreset
swift run dmlesson presets create-from-project /tmp/Intro.dmlm --output /tmp/workshop.dmlpreset --name "Workshop"
swift run dmlesson presets inspect /tmp/workshop.dmlpreset
swift run dmlesson presets preview /tmp/Other.dmlm --preset /tmp/workshop.dmlpreset
swift run dmlesson project create --lesson-title "Intro" --output /tmp/Intro.dmlm
swift run dmlesson project extract-assets /tmp/Intro.dmlm --output /tmp/raw-assets
swift run dmlesson project extract-assets /tmp/Intro.dmlm --output /tmp/raw-assets --json
swift run dmlesson record display --duration 10 --output /tmp/screen.mp4
swift run dmlesson record microphone --duration 10 --output /tmp/microphone.m4a --format m4a
swift run dmlesson record region --duration 10 --output /tmp/region.mp4 --x 0 --y 0 --width 1280 --height 720
swift run dmlesson record window --window-id 123 --duration 10 --output /tmp/window.mp4
swift run dmlesson record windows --json
swift run dmlesson record webcam --duration 10 --output /tmp/webcam.mov
swift run dmlesson render export /tmp/Intro.dmlm --output /tmp/lesson.mov --codec prores
swift run dmlesson render export /tmp/Intro.dmlm --output /tmp/lesson.mp4
swift run dmlesson render plan /tmp/Intro.dmlm --output /tmp/lesson.mp4 --json
swift run dmlesson render plan /tmp/Intro.dmlm --output /tmp/lesson.mp4 --resolution 1080p --fps 30 --codec h264 --json
swift run dmlesson settings defaults --json
swift run dmlesson transcript model-status --settings /tmp/settings.json --json
swift run dmlesson share package /tmp/Intro.dmlm --output /tmp/shares --final-video /tmp/lesson.mp4
swift run dmlesson share package /tmp/Intro.dmlm --output /tmp/shares --final-video /tmp/lesson.mp4 --json
EXPECTED

  LC_ALL=C sort -u "$expected" -o "$expected"
  LC_ALL=C sort -u "$actual" -o "$actual"

  if diff -u "$expected" "$actual" >"$diff_log"; then
    record_status "PASS" "documented CLI command coverage" "checked README.md and docs/USAGE.md"
    return 0
  fi

  record_status "FAIL" "documented CLI command coverage" "diff: $diff_log"
  return 1
}

cd "$repo_root"

echo "Output: $output_root"

if [[ "$build_cli" -eq 1 ]]; then
  run_step "build dmlesson" "$swift_bin" build --product dmlesson
fi

if [[ ! -x "$cli_path" ]]; then
  echo "Missing CLI binary: $cli_path" >&2
  exit 2
fi

project_url="$work_dir/Intro.dmlm"
other_project_url="$work_dir/Other.dmlm"
settings_url="$work_dir/settings.json"
screen_url="$project_url/screen.mp4"
render_url="$work_dir/lesson.mp4"
preset_url="$work_dir/workshop.dmlpreset"
raw_assets_url="$work_dir/raw-assets"
share_url="$work_dir/shares"
learnhouse_url="$work_dir/lesson-export"
connectors_url="$work_dir/connectors"
config_root="$work_dir/config"
home_dir="$work_dir/home"

mkdir -p "$config_root" "$home_dir"

run_step "help output" "$cli_path" --help
run_step "mcp server self test" "$python_bin" scripts/dmlesson-mcp-server.py --self-test

run_json "permissions status" "permissions-status" \
  "@=dict" \
  "screenRecording.granted=bool" \
  "screenRecording.settingsURL=str" \
  "microphone.granted=bool" \
  "camera.granted=bool" \
  -- "$cli_path" permissions status --json

run_json "record windows" "record-windows" \
  "@=list" \
  -- "$cli_path" record windows --json

validate_window_titles_redacted "record windows redacts titles by default" "$logs_dir/record-windows.json"

run_json "record windows title opt in" "record-windows-title-opt-in" \
  "@=list" \
  -- "$cli_path" record windows --include-window-titles --json

run_json "settings defaults" "settings-defaults" \
  "@=dict" \
  "capture.captureInteractionMetadata=bool" \
  "transcription.enabled=bool" \
  "transcription.modelPath=str" \
  "privacy.localOnlyMode=bool" \
  "integrations.learnHouseEnabled=bool" \
  -- "$cli_path" settings defaults --json

run_json "settings write defaults" "settings-write-defaults" \
  "output=str" \
  -- "$cli_path" settings write-defaults --output "$settings_url" --json

run_json "settings validate" "settings-validate" \
  "@=dict" \
  "capture.fps=int" \
  "transcription.runtime=str" \
  "privacy.localOnlyMode=bool" \
  -- "$cli_path" settings validate "$settings_url" --json

run_json "transcript model status" "transcript-model-status" \
  "@=dict" \
  "enabled=bool" \
  "runtime=str" \
  "state=str" \
  "isReady=bool" \
  "expandedModelPath=str" \
  -- "$cli_path" transcript model-status --settings "$settings_url" --json

run_json "project create" "project-create" \
  "lessonTitle=str" \
  "schemaVersion=int" \
  "issues=list" \
  -- "$cli_path" project create --lesson-title "Intro" --output "$project_url" --json

run_json "other project create" "other-project-create" \
  "lessonTitle=str" \
  "schemaVersion=int" \
  "issues=list" \
  -- "$cli_path" project create --lesson-title "Other" --output "$other_project_url" --json

run_json "project create with tilde output" "project-create-tilde-output" \
  "lessonTitle=str" \
  "schemaVersion=int" \
  "issues=list" \
  -- env HOME="$home_dir" "$cli_path" project create --lesson-title "Tilde" --output "~/Tilde.dmlm" --json

run_step "tilde output was expanded" test -f "$home_dir/Tilde.dmlm/project.json"

printf "screen" >"$screen_url"

run_json "project attach screen" "project-attach-screen" \
  "@=dict" \
  "metadata.lessonTitle=str" \
  "media.screen.relativePath=str" \
  -- "$cli_path" project attach "$project_url" --screen "$screen_url" --json

run_json "project inspect" "project-inspect" \
  "lessonTitle=str" \
  "fileCount=int" \
  "issues=list" \
  -- "$cli_path" project inspect "$project_url" --json

run_json "edit validate" "edit-validate" \
  "@=list" \
  -- "$cli_path" edit validate "$project_url" --json

run_json "edit plan" "edit-plan" \
  "sourceMediaURL=str" \
  "destinationURL=str" \
  "validationIssues=list" \
  -- "$cli_path" edit plan "$project_url" --duration 10 --output "$render_url" --json

run_json "render plan" "render-plan" \
  "lessonTitle=str" \
  "issues=list" \
  "plan.destinationURL=str" \
  -- "$cli_path" render plan "$project_url" --output "$render_url" --resolution 1080p --fps 30 --codec h264 --json

run_expected_failure "render concurrency bounds failure" "--concurrency must be an integer from 1 through 8." \
  "$cli_path" render plan "$project_url" --output "$render_url" --concurrency 99 --json

run_json "templates list" "templates-list" \
  "@=nonempty-list" \
  "0.id=str" \
  "0.name=str" \
  -- "$cli_path" templates list --json

run_json "presets list" "presets-list" \
  "@=nonempty-list" \
  "0.id=str" \
  "0.name=str" \
  -- "$cli_path" presets list --json

run_json "presets create from project" "presets-create-from-project" \
  "id=str" \
  "name=str" \
  -- "$cli_path" presets create-from-project "$project_url" --output "$preset_url" --name "Workshop" --json

run_json "presets inspect" "presets-inspect" \
  "id=str" \
  "name=str" \
  -- "$cli_path" presets inspect "$preset_url" --json

run_json "presets preview" "presets-preview" \
  "presetName=str" \
  "preservedProjectFields=list" \
  -- "$cli_path" presets preview "$other_project_url" --preset "$preset_url" --json

run_json "presets apply" "presets-apply" \
  "presetName=str" \
  "preservedProjectFields=list" \
  -- "$cli_path" presets apply "$project_url" --preset "$preset_url" --json

run_json "project extract assets" "project-extract-assets" \
  "output_directory_path=str" \
  "files=list" \
  -- "$cli_path" project extract-assets "$project_url" --output "$raw_assets_url" --json

run_json "share package" "share-package" \
  "package_path=str" \
  "manifest.files=list" \
  -- "$cli_path" share package "$project_url" --output "$share_url" --final-video "$screen_url" --json

run_json "learnhouse package" "learnhouse-package" \
  "package_path=str" \
  "archive_path=null-or-str" \
  "manifest.schema=str" \
  "manifest.learn_house.course_uuid=str" \
  -- "$cli_path" learnhouse package "$project_url" --output "$learnhouse_url" --archive --json

run_json "connector common cartridge" "connector-common-cartridge" \
  "package_path=str" \
  "archive_path=str" \
  "manifest.kind=str" \
  "manifest.primary_launch_path=str" \
  -- "$cli_path" connectors common-cartridge package "$project_url" --output "$connectors_url" --json

run_json "connector scorm" "connector-scorm" \
  "package_path=str" \
  "archive_path=str" \
  "manifest.kind=str" \
  "manifest.primary_launch_path=str" \
  -- "$cli_path" connectors scorm package "$project_url" --output "$connectors_url" --json

run_json "connector xapi" "connector-xapi" \
  "package_path=str" \
  "archive_path=str" \
  "manifest.kind=str" \
  "manifest.primary_launch_path=str" \
  -- "$cli_path" connectors xapi package "$project_url" --output "$connectors_url" --json

run_json "connector video host" "connector-video-host" \
  "package_path=str" \
  "archive_path=null-or-str" \
  "manifest.kind=str" \
  "manifest.primary_launch_path=str" \
  -- "$cli_path" connectors video-host handoff "$project_url" --output "$connectors_url" --json

run_json "config plan" "config-plan" \
  "rootPath=str" \
  "includePaths=list" \
  "excludedPaths=list" \
  -- "$cli_path" config plan "$config_root" --json

run_json "agent manifest" "agent-manifest" \
  "schemaVersion=int" \
  "project.lessonTitle=str" \
  "availableCommands=nonempty-list" \
  "workflows=nonempty-list" \
  -- "$cli_path" agent manifest "$project_url" --json

run_json "agent workflows" "agent-workflows" \
  "@=nonempty-list" \
  "0.targetSlug=str" \
  "0.steps=nonempty-list" \
  -- "$cli_path" agent workflows --target codex --json

run_json "app status" "app-status" \
  "schemaVersion=int" \
  "isAppRunning=bool" \
  "isRecording=bool" \
  "message=str" \
  -- "$cli_path" app status --json

run_expected_failure "invalid command failure" "Invalid command: not-a-command" \
  "$cli_path" not-a-command

run_expected_failure "missing project create title failure" "Usage: dmlesson project create" \
  "$cli_path" project create --output "$work_dir/MissingTitle.dmlm"

run_expected_failure "option value rejects flag token" "Missing value for --output." \
  "$cli_path" project create --lesson-title "Intro" --output --json

check_documented_commands

echo
echo "Summary: ${pass_count} passed, ${fail_count} failed"
if [[ "$keep_output" -eq 1 ]]; then
  echo "Keeping output directory: $output_root"
else
  echo "Output directory removed. Re-run with --keep-output to inspect logs."
fi

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
