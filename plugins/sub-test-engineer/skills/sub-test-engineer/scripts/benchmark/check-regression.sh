#!/usr/bin/env bash
# check-regression.sh — Checks benchmark results against regression thresholds.
# Usage: check-regression.sh <current-dir> [baseline-dir]
#
# Reads thresholds from thresholds.yml (same directory as this script).
# If baseline-dir provided: checks both absolute thresholds AND regression thresholds.
# If no baseline-dir: checks only absolute thresholds.
#
# Exit code 0 if all checks pass, 1 if any fail.

set -euo pipefail

CURRENT_DIR="${1:?Usage: check-regression.sh <current-dir> [baseline-dir]}"
BASELINE_DIR="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THRESHOLDS_FILE="$SCRIPT_DIR/thresholds.yml"

if [ ! -d "$CURRENT_DIR" ]; then
    echo "ERROR: Current directory not found: $CURRENT_DIR" >&2
    exit 1
fi

if [ ! -f "$THRESHOLDS_FILE" ]; then
    echo "ERROR: Thresholds file not found: $THRESHOLDS_FILE" >&2
    exit 1
fi

if [ -n "$BASELINE_DIR" ] && [ ! -d "$BASELINE_DIR" ]; then
    echo "ERROR: Baseline directory not found: $BASELINE_DIR" >&2
    exit 1
fi

# --- Run regression checks ---
python3 << 'PYTHON_EOF' "$CURRENT_DIR" "$BASELINE_DIR" "$THRESHOLDS_FILE"
import json
import os
import sys

current_dir = sys.argv[1]
baseline_dir = sys.argv[2] if sys.argv[2] else None
thresholds_file = sys.argv[3]

# --- Parse thresholds ---
try:
    import yaml
    with open(thresholds_file) as f:
        config = yaml.safe_load(f)
    thresholds = config.get("regression-thresholds", {})
except ImportError:
    # Fallback: simple regex-based YAML parsing for flat structure
    import re
    thresholds = {}
    current_section = None
    with open(thresholds_file) as f:
        for line in f:
            line = line.rstrip()
            if not line or line.lstrip().startswith("#"):
                continue
            # Top-level key (regression-thresholds:)
            if line.startswith("regression-thresholds:"):
                continue
            # Section key (e.g., "  compile-success-rate:")
            m = re.match(r"^  (\S[^:]+):\s*$", line)
            if m:
                current_section = m.group(1)
                thresholds[current_section] = {}
                continue
            # Value key (e.g., "    min-absolute: 70")
            m = re.match(r"^\s{4}(\S[^:]+):\s*(\S+)", line)
            if m and current_section:
                key = m.group(1)
                val = m.group(2)
                # Strip inline comments
                val = val.split("#")[0].strip()
                try:
                    thresholds[current_section][key] = int(val)
                except ValueError:
                    try:
                        thresholds[current_section][key] = float(val)
                    except ValueError:
                        thresholds[current_section][key] = val

def load_project_jsons(directory):
    """Load all JSON files from a directory, keyed by filename."""
    projects = {}
    if not directory or not os.path.isdir(directory):
        return projects
    for fname in sorted(os.listdir(directory)):
        if not fname.endswith(".json"):
            continue
        fpath = os.path.join(directory, fname)
        try:
            with open(fpath) as f:
                data = json.load(f)
            projects[fname] = data
        except (json.JSONDecodeError, IOError) as e:
            print(f"WARN: Skipping {fname}: {e}", file=sys.stderr)
    return projects

def safe_num(value):
    """Convert a value to float, returning None if not numeric."""
    if value is None:
        return None
    if isinstance(value, bool):
        return 100.0 if value else 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

# Load data
current_projects = load_project_jsons(current_dir)
baseline_projects = load_project_jsons(baseline_dir) if baseline_dir else {}

if not current_projects:
    print("ERROR: No JSON files found in current directory.", file=sys.stderr)
    sys.exit(1)

total_projects = 0
total_checks = 0
passed_checks = 0
failed_checks = 0

for fname, current in sorted(current_projects.items()):
    project_name = current.get("project_name", fname.replace(".json", ""))
    baseline = baseline_projects.get(fname)
    total_projects += 1

    print(f"=== Regression Check: {project_name} ===")

    # --- compile-success-rate ---
    compile_thresh = thresholds.get("compile-success-rate", {})
    compile_val = safe_num(current.get("compile_success"))
    if compile_val is not None:
        min_abs = compile_thresh.get("min-absolute", 0)
        total_checks += 1
        if compile_val >= min_abs:
            passed_checks += 1
            print(f"  PASS: compile-success-rate = {compile_val:.0f}% (min: {min_abs}%)")
        else:
            failed_checks += 1
            print(f"  FAIL: compile-success-rate = {compile_val:.0f}% (min: {min_abs}%)")

        if baseline:
            baseline_val = safe_num(baseline.get("compile_success"))
            if baseline_val is not None:
                max_reg = compile_thresh.get("max-regression", 100)
                regression = baseline_val - compile_val
                total_checks += 1
                if regression <= max_reg:
                    passed_checks += 1
                    print(f"  PASS: compile-success-rate regression = {regression:.1f}%p (max: {max_reg}%)")
                else:
                    failed_checks += 1
                    print(f"  FAIL: compile-success-rate regression = {regression:.1f}%p (max: {max_reg}%)")

    # --- test-pass-rate ---
    test_thresh = thresholds.get("test-pass-rate", {})
    tests_total = safe_num(current.get("tests_total"))
    tests_passed = safe_num(current.get("tests_passed"))
    if tests_total is not None and tests_total > 0 and tests_passed is not None:
        pass_rate = (tests_passed / tests_total) * 100
        min_abs = test_thresh.get("min-absolute", 0)
        total_checks += 1
        if pass_rate >= min_abs:
            passed_checks += 1
            print(f"  PASS: test-pass-rate = {pass_rate:.1f}% (min: {min_abs}%)")
        else:
            failed_checks += 1
            print(f"  FAIL: test-pass-rate = {pass_rate:.1f}% (min: {min_abs}%)")

        if baseline:
            b_total = safe_num(baseline.get("tests_total"))
            b_passed = safe_num(baseline.get("tests_passed"))
            if b_total and b_total > 0 and b_passed is not None:
                b_pass_rate = (b_passed / b_total) * 100
                max_reg = test_thresh.get("max-regression", 100)
                regression = b_pass_rate - pass_rate
                total_checks += 1
                if regression <= max_reg:
                    passed_checks += 1
                    print(f"  PASS: test-pass-rate regression = {regression:.1f}%p (max: {max_reg}%)")
                else:
                    failed_checks += 1
                    print(f"  FAIL: test-pass-rate regression = {regression:.1f}%p (max: {max_reg}%)")

    # --- coverage-delta ---
    cov_thresh = thresholds.get("coverage-delta", {})
    coverage_val = safe_num(current.get("coverage_line_pct"))
    if coverage_val is not None:
        min_abs = cov_thresh.get("min-absolute", 0)
        total_checks += 1
        if coverage_val >= min_abs:
            passed_checks += 1
            print(f"  PASS: coverage-delta = {coverage_val:.1f}%p (min: {min_abs}%p)")
        else:
            failed_checks += 1
            print(f"  FAIL: coverage-delta = {coverage_val:.1f}%p (min: {min_abs}%p)")

        if baseline:
            b_cov = safe_num(baseline.get("coverage_line_pct"))
            if b_cov is not None:
                max_reg = cov_thresh.get("max-regression", 100)
                regression = b_cov - coverage_val
                total_checks += 1
                if regression <= max_reg:
                    passed_checks += 1
                    print(f"  PASS: coverage-delta regression = {regression:.1f}%p (max: {max_reg}%p)")
                else:
                    failed_checks += 1
                    print(f"  FAIL: coverage-delta regression = {regression:.1f}%p (max: {max_reg}%p)")

    # --- mutation-kill-rate (only if non-null) ---
    mut_thresh = thresholds.get("mutation-kill-rate", {})
    mutation_val = current.get("mutation_kill_pct")
    if mutation_val is not None:
        mutation_num = safe_num(mutation_val)
        if mutation_num is not None:
            min_abs = mut_thresh.get("min-absolute", 0)
            total_checks += 1
            if mutation_num >= min_abs:
                passed_checks += 1
                print(f"  PASS: mutation-kill-rate = {mutation_num:.1f}% (min: {min_abs}%)")
            else:
                failed_checks += 1
                print(f"  FAIL: mutation-kill-rate = {mutation_num:.1f}% (min: {min_abs}%)")

            if baseline:
                b_mut = baseline.get("mutation_kill_pct")
                if b_mut is not None:
                    b_mut_num = safe_num(b_mut)
                    if b_mut_num is not None:
                        max_reg = mut_thresh.get("max-regression", 100)
                        regression = b_mut_num - mutation_num
                        total_checks += 1
                        if regression <= max_reg:
                            passed_checks += 1
                            print(f"  PASS: mutation-kill-rate regression = {regression:.1f}%p (max: {max_reg}%)")
                        else:
                            failed_checks += 1
                            print(f"  FAIL: mutation-kill-rate regression = {regression:.1f}%p (max: {max_reg}%)")
    else:
        print(f"  SKIP: mutation-kill-rate (null — mutation not enabled)")

    print()

# --- Summary ---
print("=== Summary ===")
print(f"Projects: {total_projects} | Checks: {total_checks} | Passed: {passed_checks} | Failed: {failed_checks}")

if failed_checks > 0:
    sys.exit(1)
else:
    sys.exit(0)
PYTHON_EOF
