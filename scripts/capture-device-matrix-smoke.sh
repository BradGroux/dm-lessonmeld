#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage: scripts/capture-device-matrix-smoke.sh [--record|--all] [--duration seconds] [--output directory] [--keep-output]

Runs the local capture device-matrix smoke harness.

Defaults are non-capturing: build the CLI, report permission status, and mark
device captures as skipped/manual. Use --record to run display, region, and
screen-only project captures. Use --all to also opt into microphone, webcam,
system-audio, and combined capture checks.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_bin="${SWIFT:-swift}"
swiftc_bin="${SWIFTC:-swiftc}"
python_bin="${PYTHON:-python3}"
duration="${LESSONMELD_CAPTURE_SMOKE_DURATION:-2}"
output_root=""
record=0
include_microphone=0
include_webcam=0
include_system_audio=0
include_combined=0
keep_output=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --record)
      record=1
      shift
      ;;
    --all)
      record=1
      include_microphone=1
      include_webcam=1
      include_system_audio=1
      include_combined=1
      shift
      ;;
    --with-microphone)
      include_microphone=1
      shift
      ;;
    --with-webcam)
      include_webcam=1
      shift
      ;;
    --with-system-audio)
      include_system_audio=1
      shift
      ;;
    --with-combined)
      include_combined=1
      shift
      ;;
    --duration)
      duration="${2:-}"
      shift 2
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

if ! [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Duration must be a positive number of seconds." >&2
  exit 2
fi

if [[ -z "$output_root" ]]; then
  output_root="${TMPDIR:-/tmp}/dm-lessonmeld-capture-smoke-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$output_root/logs"
summary_file="$output_root/summary.tsv"
cli_path="$repo_root/.build/debug/dmlesson"
pass_count=0
skip_count=0
manual_count=0
fail_count=0
fixture_pid=""
fixture_window_id=""

printf "status\tcheck\tdetail\n" > "$summary_file"

record_status() {
  local status="$1"
  local name="$2"
  local detail="$3"
  printf "%s\t%s\t%s\n" "$status" "$name" "$detail" >> "$summary_file"
  printf "[%s] %s - %s\n" "$status" "$name" "$detail"
  case "$status" in
    PASS) pass_count=$((pass_count + 1)) ;;
    SKIP) skip_count=$((skip_count + 1)) ;;
    MANUAL) manual_count=$((manual_count + 1)) ;;
    FAIL) fail_count=$((fail_count + 1)) ;;
  esac
}

cleanup_window_fixture() {
  if [[ -n "$fixture_pid" ]] && kill -0 "$fixture_pid" 2>/dev/null; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  fixture_pid=""
}

trap cleanup_window_fixture EXIT

start_window_fixture() {
  local fixture_binary="$output_root/LessonMeldFixture"
  local fixture_log="$output_root/logs/window_capture_fixture.log"
  local listing_log="$output_root/logs/window_capture_fixture_windows.json"

  if "$swiftc_bin" -parse-as-library "$repo_root/scripts/fixtures/WindowCaptureFixture.swift" -o "$fixture_binary" >"$fixture_log" 2>&1; then
    record_status "PASS" "build window capture fixture" "log: $fixture_log"
  else
    record_status "FAIL" "build window capture fixture" "log: $fixture_log"
    return 1
  fi

  "$fixture_binary" >>"$fixture_log" 2>&1 &
  fixture_pid=$!

  for _ in {1..30}; do
    if ! kill -0 "$fixture_pid" 2>/dev/null; then
      record_status "FAIL" "launch window capture fixture" "fixture exited before publishing a window; log: $fixture_log"
      return 1
    fi
    if "$cli_path" record windows --json >"$listing_log" 2>>"$fixture_log"; then
      fixture_window_id="$($python_bin -c 'import json, sys; windows = json.load(open(sys.argv[1])); print(next((str(window["id"]) for window in windows if window.get("ownerName") == "LessonMeldFixture"), ""))' "$listing_log")"
      if [[ -n "$fixture_window_id" ]]; then
        record_status "PASS" "launch window capture fixture" "window id: $fixture_window_id"
        return 0
      fi
    fi
    sleep 0.1
  done

  record_status "FAIL" "launch window capture fixture" "fixture window was not listed; log: $fixture_log"
  return 1
}

validate_stale_window_error() {
  local log_path="$output_root/logs/stale_window_error.log"
  local output_path="$output_root/stale-window.mp4"
  if "$cli_path" record window --window-id 4294967295 --duration "$duration" --output "$output_path" --json >"$log_path" 2>&1; then
    record_status "FAIL" "stale window rejection" "unexpected success; log: $log_path"
    return 1
  fi
  if grep -q "Requested window was not found: 4294967295" "$log_path" && [[ ! -e "$output_path" ]]; then
    record_status "PASS" "stale window rejection" "sanitized error without output; log: $log_path"
    return 0
  fi
  record_status "FAIL" "stale window rejection" "missing expected error or partial output exists; log: $log_path"
  return 1
}

run_step() {
  local name="$1"
  shift
  local log_name
  log_name="$(echo "$name" | tr ' /' '__' | tr -cd '[:alnum:]_.-')"
  local log_path="$output_root/logs/${log_name}.log"

  if "$@" >"$log_path" 2>&1; then
    record_status "PASS" "$name" "log: $log_path"
    return 0
  fi

  record_status "FAIL" "$name" "log: $log_path"
  return 1
}

validate_file() {
  local name="$1"
  local path="$2"
  if [[ -s "$path" ]]; then
    record_status "PASS" "$name artifact" "$path ($(wc -c < "$path" | tr -d ' ') bytes)"
    return 0
  fi

  record_status "FAIL" "$name artifact" "missing or empty: $path"
  return 1
}

skip_capture() {
  local name="$1"
  local reason="$2"
  record_status "SKIP" "$name" "$reason"
}

cd "$repo_root" || exit 2

echo "Output: $output_root"
run_step "build CLI" "$swift_bin" build --product dmlesson
run_step "permissions status" "$cli_path" permissions status --json
run_step "window listing" "$cli_path" record windows --json

if [[ "$record" -eq 1 ]]; then
  display_file="$output_root/display.mp4"
  if run_step "display capture" "$cli_path" record display --duration "$duration" --output "$display_file" --json; then
    validate_file "display capture" "$display_file"
  fi

  region_file="$output_root/region.mp4"
  if run_step "region capture" "$cli_path" record region --duration "$duration" --output "$region_file" --x 0 --y 0 --width 640 --height 360 --json; then
    validate_file "region capture" "$region_file"
  fi

  project_dir="$output_root/project-screen.dmlm"
  if run_step "screen project capture" "$cli_path" record project --duration "$duration" --output "$project_dir" --lesson-title "Capture Smoke Screen" --json; then
    run_step "screen project inspect" "$cli_path" project inspect "$project_dir" --json
    validate_file "screen project media" "$project_dir/screen.mp4"
  fi

  if start_window_fixture; then
    window_file="$output_root/window.mp4"
    if run_step "window capture" "$cli_path" record window --window-id "$fixture_window_id" --duration "$duration" --output "$window_file" --json; then
      validate_file "window capture" "$window_file"
    fi

    window_project_dir="$output_root/project-window.dmlm"
    if run_step "window project capture" "$cli_path" record project --window-id "$fixture_window_id" --duration "$duration" --output "$window_project_dir" --lesson-title "Capture Smoke Window" --json; then
      run_step "window project inspect" "$cli_path" project inspect "$window_project_dir" --json
      validate_file "window project media" "$window_project_dir/screen.mp4"
    fi
    cleanup_window_fixture
  fi
  validate_stale_window_error
else
  skip_capture "display capture" "pass --record or --all to create local recordings"
  skip_capture "region capture" "pass --record or --all to create local recordings"
  skip_capture "screen project capture" "pass --record or --all to create local recordings"
  skip_capture "window capture" "pass --record or --all to create a controlled fixture window recording"
  skip_capture "window project capture" "pass --record or --all to create a controlled fixture window project"
  skip_capture "stale window rejection" "pass --record or --all to validate sanitized window errors"
fi

if [[ "$record" -eq 1 && "$include_system_audio" -eq 1 ]]; then
  system_audio_file="$output_root/display-system-audio.mp4"
  if run_step "display plus system audio capture" "$cli_path" record display --duration "$duration" --output "$system_audio_file" --system-audio --json; then
    validate_file "display plus system audio capture" "$system_audio_file"
  fi
else
  skip_capture "display plus system audio capture" "pass --all or --with-system-audio with --record"
fi

if [[ "$record" -eq 1 && "$include_microphone" -eq 1 ]]; then
  microphone_file="$output_root/microphone.m4a"
  if run_step "microphone capture" "$cli_path" record microphone --duration "$duration" --output "$microphone_file" --format m4a --json; then
    validate_file "microphone capture" "$microphone_file"
  fi
else
  skip_capture "microphone capture" "pass --all or --with-microphone with --record"
fi

if [[ "$record" -eq 1 && "$include_webcam" -eq 1 ]]; then
  webcam_file="$output_root/webcam.mov"
  if run_step "webcam capture" "$cli_path" record webcam --duration "$duration" --output "$webcam_file" --json; then
    validate_file "webcam capture" "$webcam_file"
  fi
else
  skip_capture "webcam capture" "pass --all or --with-webcam with --record"
fi

if [[ "$record" -eq 1 && "$include_combined" -eq 1 ]]; then
  combined_dir="$output_root/project-combined.dmlm"
  combined_args=(record project --duration "$duration" --output "$combined_dir" --lesson-title "Capture Smoke Combined" --microphone --webcam --system-audio --json)
  if run_step "combined screen microphone webcam system audio capture" "$cli_path" "${combined_args[@]}"; then
    run_step "combined project inspect" "$cli_path" project inspect "$combined_dir" --json
    validate_file "combined screen media" "$combined_dir/screen.mp4"
    validate_file "combined microphone media" "$combined_dir/microphone.m4a"
    validate_file "combined webcam media" "$combined_dir/webcam.mov"
  fi
else
  skip_capture "combined capture" "pass --all or --with-combined with --record"
fi

record_status "MANUAL" "app window capture" "record the controlled fixture or another safe window from the app Window mode and verify the output"
record_status "MANUAL" "permission denied or revoked" "revoke Screen Recording, Microphone, or Camera in System Settings, rerun the relevant capture, and verify the error is explicit"
record_status "MANUAL" "missing camera or microphone" "run on hardware without that device or disable it at the OS/device layer and verify the row reports a clear failure"
record_status "MANUAL" "stop timeout and cancel timing" "start from the app control bar, stop immediately, and verify the status leaves Stopping"

echo
echo "Summary: ${pass_count} passed, ${skip_count} skipped, ${manual_count} manual, ${fail_count} failed"
echo "Summary file: $summary_file"

if [[ "$keep_output" -eq 0 ]]; then
  echo "Output directory is disposable. Re-run with --keep-output when preserving artifacts for a bug report."
else
  echo "Keeping output directory: $output_root"
fi

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
