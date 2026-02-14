#!/usr/bin/env bash
# compare-runs.sh — Compares two benchmark result directories and produces a markdown comparison table.
# Usage: compare-runs.sh <baseline-dir> <current-dir> [output-file]
#
# Both directories should contain JSON files (one per project, e.g., petclinic-kotlin.json)
# with fields: project_name, compile_success, tests_total, tests_passed, tests_failed,
#              coverage_line_pct, coverage_branch_pct, mutation_kill_pct, generated_test_files

set -euo pipefail

BASELINE_DIR="${1:?Usage: compare-runs.sh <baseline-dir> <current-dir> [output-file]}"
CURRENT_DIR="${2:?Usage: compare-runs.sh <baseline-dir> <current-dir> [output-file]}"
OUTPUT_FILE="${3:-}"

if [ ! -d "$BASELINE_DIR" ]; then
    echo "ERROR: Baseline directory not found: $BASELINE_DIR" >&2
    exit 1
fi

if [ ! -d "$CURRENT_DIR" ]; then
    echo "ERROR: Current directory not found: $CURRENT_DIR" >&2
    exit 1
fi

# --- Generate comparison using python3 ---
REPORT=$(python3 << 'PYTHON_EOF'
import json
import os
import sys

baseline_dir = sys.argv[1]
current_dir = sys.argv[2]

def load_project_jsons(directory):
    """Load all JSON files from a directory, keyed by filename."""
    projects = {}
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
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def format_val(value):
    """Format a value for display."""
    if value is None:
        return "N/A"
    if isinstance(value, bool):
        return "PASS" if value else "FAIL"
    if isinstance(value, float):
        if value == int(value):
            return str(int(value))
        return f"{value:.1f}"
    return str(value)

def format_delta(delta):
    """Format a delta value with sign."""
    if delta is None:
        return "N/A"
    if isinstance(delta, float):
        if delta == int(delta):
            delta = int(delta)
            return f"+{delta}" if delta > 0 else str(delta)
        return f"+{delta:.1f}" if delta > 0 else f"{delta:.1f}"
    return str(delta)

def status_label(delta):
    """Return status label based on delta."""
    if delta is None:
        return "N/A"
    if delta > 0:
        return "IMPROVED"
    if delta < 0:
        return "REGRESSED"
    return "SAME"

# Metrics to compare: (display_name, json_key, is_boolean)
METRICS = [
    ("compile_success",      "compile_success",      True),
    ("tests_total",          "tests_total",           False),
    ("tests_passed",         "tests_passed",          False),
    ("tests_failed",         "tests_failed",          False),
    ("coverage_line_pct",    "coverage_line_pct",     False),
    ("coverage_branch_pct",  "coverage_branch_pct",   False),
    ("mutation_kill_pct",    "mutation_kill_pct",      False),
    ("generated_test_files", "generated_test_files",  False),
]

baseline_projects = load_project_jsons(baseline_dir)
current_projects = load_project_jsons(current_dir)

# Find common projects
common_files = sorted(set(baseline_projects.keys()) & set(current_projects.keys()))

if not common_files:
    print("No common project files found between baseline and current directories.", file=sys.stderr)
    sys.exit(1)

# Track summary counts
total_metrics = 0
improved_count = 0
regressed_count = 0
unchanged_count = 0

lines = []
lines.append("# Benchmark Comparison Report")
lines.append("")
lines.append(f"- Baseline: `{baseline_dir}`")
lines.append(f"- Current:  `{current_dir}`")
lines.append(f"- Projects compared: {len(common_files)}")
lines.append("")
lines.append("## Comparison Table")
lines.append("")
lines.append("| Project | Metric | Baseline | Current | Delta | Status |")
lines.append("|---------|--------|----------|---------|-------|--------|")

for fname in common_files:
    baseline = baseline_projects[fname]
    current = current_projects[fname]
    project_name = current.get("project_name", fname.replace(".json", ""))

    for display_name, key, is_bool in METRICS:
        b_val = baseline.get(key)
        c_val = current.get(key)

        if is_bool:
            # For booleans: convert to 1/0 for delta
            b_num = 1 if b_val else 0
            c_num = 1 if c_val else 0
            delta = c_num - b_num
            b_display = "PASS" if b_val else "FAIL"
            c_display = "PASS" if c_val else "FAIL"
            delta_display = format_delta(delta)
        else:
            b_num = safe_num(b_val)
            c_num = safe_num(c_val)
            if b_num is not None and c_num is not None:
                delta = c_num - b_num
            else:
                delta = None
            b_display = format_val(b_val)
            c_display = format_val(c_val)
            delta_display = format_delta(delta)

        status = status_label(delta)

        # Track summary
        if delta is not None:
            total_metrics += 1
            if delta > 0:
                improved_count += 1
            elif delta < 0:
                regressed_count += 1
            else:
                unchanged_count += 1

        lines.append(f"| {project_name} | {display_name} | {b_display} | {c_display} | {delta_display} | {status} |")

lines.append("")
lines.append("## Summary")
lines.append("")
lines.append(f"- **Projects compared:** {len(common_files)}")
lines.append(f"- **Total metrics compared:** {total_metrics}")
lines.append(f"- **Improved:** {improved_count}")
lines.append(f"- **Regressed:** {regressed_count}")
lines.append(f"- **Unchanged:** {unchanged_count}")
lines.append("")

# Report projects only in one directory
only_baseline = sorted(set(baseline_projects.keys()) - set(current_projects.keys()))
only_current = sorted(set(current_projects.keys()) - set(baseline_projects.keys()))

if only_baseline or only_current:
    lines.append("## Unmatched Projects")
    lines.append("")
    if only_baseline:
        lines.append(f"- Only in baseline: {', '.join(only_baseline)}")
    if only_current:
        lines.append(f"- Only in current: {', '.join(only_current)}")
    lines.append("")

print("\n".join(lines))
PYTHON_EOF
)

# --- Output ---
if [ -n "$OUTPUT_FILE" ]; then
    echo "$REPORT" > "$OUTPUT_FILE"
    echo "[Compare] Report written to: $OUTPUT_FILE"
else
    echo "$REPORT"
fi
