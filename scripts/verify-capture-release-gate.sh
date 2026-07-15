#!/usr/bin/env bash
set -euo pipefail

if [[ "${#}" -ne 4 ]]; then
  echo "usage: scripts/verify-capture-release-gate.sh REPORT EXPECTED_REVISION EXPECTED_REPOSITORY EXPECTED_RUN_ID" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
expected_revision = sys.argv[2]
expected_repository = sys.argv[3]
expected_run_id = sys.argv[4]


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


if not report_path.is_file():
    fail(f"capture release gate report not found: {report_path}")

try:
    report = json.loads(report_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    fail(f"capture release gate report is invalid JSON: {error}")

if not isinstance(report, dict):
    fail("capture release gate report must be a JSON object")

expected_schema = "io.digitalmeld.dm-lessonmeld.capture-release-gate.v1"
if report.get("schema") != expected_schema:
    fail(f"capture release gate schema must be {expected_schema}")

if report.get("revision") != expected_revision:
    fail("capture release gate revision does not match release commit")
if report.get("repository") != expected_repository:
    fail("capture release gate repository does not match release repository")
if str(report.get("workflowRunId", "")) != expected_run_id:
    fail("capture release gate workflow run ID does not match downloaded artifact")

for metadata_field in ("recordedAt", "actor"):
    value = report.get(metadata_field)
    if not isinstance(value, str) or not value.strip():
        fail(f"capture release gate {metadata_field} is missing")

results = report.get("results")
if not isinstance(results, dict):
    fail("capture release gate results are missing")

sha256_pattern = re.compile(r"[0-9a-f]{64}")
for result_name in ("captureDeviceMatrix", "realMediaFixture"):
    result = results.get(result_name)
    if not isinstance(result, dict):
        fail(f"capture release gate {result_name} result is missing")
    if result.get("status") != "passed":
        fail(f"capture release gate {result_name} status must be passed")
    digest = result.get("summarySha256")
    if not isinstance(digest, str) or sha256_pattern.fullmatch(digest) is None:
        fail(f"capture release gate {result_name} summary SHA-256 is invalid")

manual_checks = results.get("manualChecks")
if not isinstance(manual_checks, dict):
    fail("capture release gate manualChecks result is missing")
if manual_checks.get("status") != "passed":
    fail("capture release gate manualChecks status must be passed")
notes = manual_checks.get("notes")
if not isinstance(notes, str) or not notes.strip():
    fail("capture release gate manualChecks notes are missing")

print(f"revision={expected_revision}")
print(f"workflow_run_id={expected_run_id}")
print("capture_gate=passed")
PY
