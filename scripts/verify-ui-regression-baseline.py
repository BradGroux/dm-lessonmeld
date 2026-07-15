#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare a rendered UI fingerprint with its reviewed baseline.")
    parser.add_argument("report", type=Path)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--update", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = json.loads(args.report.read_text())
    fingerprint = report.get("fingerprint")
    if not report.get("passed") or not fingerprint:
        raise SystemExit("report did not contain a passing rendered screenshot fingerprint")

    reviewed = {
        "appearance": report["appearance"],
        "columns": fingerprint["columns"],
        "fixture_id": report["fixtureID"],
        "luminance": fingerprint["luminance"],
        "maximum_mean_absolute_difference": 0.12,
        "rows": fingerprint["rows"],
    }
    if args.update:
        args.baseline.parent.mkdir(parents=True, exist_ok=True)
        args.baseline.write_text(json.dumps(reviewed, indent=2, sort_keys=True) + "\n")
        print(f"Updated reviewed screenshot fingerprint: {args.baseline}")
        return 0

    if not args.baseline.is_file():
        raise SystemExit(f"reviewed screenshot fingerprint is missing: {args.baseline}")
    baseline = json.loads(args.baseline.read_text())
    for key in ("fixture_id", "appearance", "columns", "rows"):
        if reviewed[key] != baseline.get(key):
            raise SystemExit(f"screenshot fingerprint metadata mismatch for {key}")

    actual_values = reviewed["luminance"]
    baseline_values = baseline.get("luminance", [])
    if len(actual_values) != len(baseline_values) or not actual_values:
        raise SystemExit("screenshot fingerprint sample count mismatch")
    difference = sum(abs(actual - expected) for actual, expected in zip(actual_values, baseline_values)) / len(actual_values)
    threshold = float(baseline.get("maximum_mean_absolute_difference", 0.12))
    print(f"Screenshot fingerprint mean absolute difference: {difference:.4f} (limit {threshold:.4f})")
    if difference > threshold:
        raise SystemExit("rendered screenshot differs from the reviewed structural baseline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
