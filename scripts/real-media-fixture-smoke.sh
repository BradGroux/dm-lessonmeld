#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage: scripts/real-media-fixture-smoke.sh [--video file.mp4|file.mov] [--project project.dmlm] [--render] [--output directory] [--keep-output]

Runs local real-media fixture checks without committing media files. Pass one or
more --video or --project values. Video fixtures are copied into disposable
.dmlm bundles, attached as screen media, inspected, and render-planned. Project
fixtures are inspected and render-planned in place. Use --render to export final
MP4 files too.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_bin="${SWIFT:-swift}"
output_root=""
keep_output=0
render=0
videos=()
projects=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video)
      videos+=("${2:-}")
      shift 2
      ;;
    --project)
      projects+=("${2:-}")
      shift 2
      ;;
    --render)
      render=1
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

if [[ "${#videos[@]}" -eq 0 && "${#projects[@]}" -eq 0 ]]; then
  echo "Provide at least one --video or --project fixture." >&2
  usage >&2
  exit 2
fi

if [[ -z "$output_root" ]]; then
  output_root="${TMPDIR:-/tmp}/dm-lessonmeld-real-media-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$output_root/logs" "$output_root/work" "$output_root/renders"
summary_file="$output_root/summary.tsv"
cli_path="$repo_root/.build/debug/dmlesson"
pass_count=0
fail_count=0

printf "status\tcheck\tdetail\n" > "$summary_file"

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

safe_name() {
  local value="$1"
  value="$(basename "$value")"
  value="${value%.*}"
  printf "%s" "$value" | tr '[:upper:] /' '[:lower:]-_' | tr -cd '[:alnum:]_.-'
}

run_step() {
  local name="$1"
  shift
  local log_name log_path
  log_name="$(printf "%s" "$name" | tr ' /' '__' | tr -cd '[:alnum:]_.-')"
  log_path="$output_root/logs/${log_name}.log"

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

check_fixture_path() {
  local kind="$1"
  local path="$2"
  if [[ -z "$path" || ! -e "$path" ]]; then
    record_status "FAIL" "$kind fixture exists" "missing: $path"
    return 1
  fi
  record_status "PASS" "$kind fixture exists" "$path"
  return 0
}

cd "$repo_root" || exit 2

echo "Output: $output_root"
run_step "build CLI" "$swift_bin" build --product dmlesson

if [[ "${#videos[@]}" -gt 0 ]]; then
  for video in "${videos[@]}"; do
    check_fixture_path "video" "$video" || continue
    extension="${video##*.}"
    extension="$(printf "%s" "$extension" | tr '[:upper:]' '[:lower:]')"
    case "$extension" in
      mp4|mov) ;;
      *)
        record_status "FAIL" "video fixture type" "expected mp4 or mov: $video"
        continue
        ;;
    esac

    slug="$(safe_name "$video")"
    project_dir="$output_root/work/${slug}.dmlm"
    screen_file="$project_dir/screen.${extension}"
    render_file="$output_root/renders/${slug}.mp4"
    mkdir -p "$project_dir"
    if cp "$video" "$screen_file"; then
      record_status "PASS" "copy video fixture ${slug}" "$screen_file"
    else
      record_status "FAIL" "copy video fixture ${slug}" "$screen_file"
      continue
    fi

    run_step "create project ${slug}" "$cli_path" project create --lesson-title "$slug" --output "$project_dir" --json
    run_step "attach video ${slug}" "$cli_path" project attach "$project_dir" --screen "$screen_file" --json
    run_step "inspect project ${slug}" "$cli_path" project inspect "$project_dir" --json
    run_step "render plan ${slug}" "$cli_path" render plan "$project_dir" --output "$render_file" --json
    if [[ "$render" -eq 1 ]]; then
      if run_step "render export ${slug}" "$cli_path" render export "$project_dir" --output "$render_file" --json; then
        validate_file "render export ${slug}" "$render_file"
      fi
    fi
  done
fi

if [[ "${#projects[@]}" -gt 0 ]]; then
  for project in "${projects[@]}"; do
    check_fixture_path "project" "$project" || continue
    slug="$(safe_name "$project")"
    render_file="$output_root/renders/${slug}.mp4"

    run_step "inspect fixture project ${slug}" "$cli_path" project inspect "$project" --json
    run_step "render plan fixture project ${slug}" "$cli_path" render plan "$project" --output "$render_file" --json
    if [[ "$render" -eq 1 ]]; then
      if run_step "render export fixture project ${slug}" "$cli_path" render export "$project" --output "$render_file" --json; then
        validate_file "render export fixture project ${slug}" "$render_file"
      fi
    fi
  done
fi

echo
echo "Summary: ${pass_count} passed, ${fail_count} failed"
echo "Summary file: $summary_file"

if [[ "$keep_output" -eq 0 ]]; then
  echo "Output directory is disposable. Re-run with --keep-output when preserving artifacts for a bug report."
else
  echo "Keeping output directory: $output_root"
fi

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
