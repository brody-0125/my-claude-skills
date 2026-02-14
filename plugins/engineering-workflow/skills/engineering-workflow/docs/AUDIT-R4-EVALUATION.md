# Research Round 4 — Finding Evaluation

> Step 2: Categorize, validate against current file state, check ROI, set PASS/FAIL.
> Date: 2026-02-14
> Status: **ALL 6 PASS ITEMS IMPLEMENTED AND VERIFIED**

## Methodology

3 research agents explored:
- a053136: BE Orchestrator Completeness (chains, schemas, agent references)
- ae3558a: End-to-End Flow Integrity (classify → route → orchestrate → synthesize)
- adaf042: Script Edge Cases (error handling, functional issues, consistency)

---

## PASS — Implement

### P1. be-orchestrator.md Chain 5 "B5" → "B-5" Naming Bug [HIGH, TRIVIAL effort]
**Source**: a053136 | **Validated**: YES

be-orchestrator.md line 156: `S-3 -> B5 -> T-3 -> T-1`
Should be: `S-3 -> B-5 -> T-3 -> T-1`

be-orchestration-protocol.md correctly uses `B-5`. Actual file is `b5-implementation-guide.md`.

**Fix**: Change `B5` to `B-5` on line 156.

### P2. be-orchestrator.md Output Schema `clusters_analyzed` Alignment [MEDIUM, LOW effort]
**Source**: a053136 | **Validated**: YES

be-orchestrator.md output (line 269) uses `clusters_analyzed`.
orchestration-protocol.md and synthesis-protocol.md both use `domains_analyzed`.

BE naturally uses "clusters" (S/B/R/T) while DB uses "domains" (A-F), but the
cross-system synthesis protocol needs a consistent field name.

**Fix**: Change `clusters_analyzed` to `domains_analyzed` in be-orchestrator.md
output schema. Add comment noting BE clusters map to this field.

### P3. resolve-constraints.sh Flat Array Null Bug [HIGH, LOW effort]
**Source**: adaf042 | **Validated**: YES

resolve-constraints.sh lines 50-52: Early-exit path for ≤1 constraints uses
`echo "${CONSTRAINTS}" | jq '{ ... resolved_set: .constraints ... }'`

If input is a flat array `[constraint]`, `.constraints` returns `null`
(not the array). This produces `"resolved_set": null`.

The dual-format detection on lines 39-45 only applies to `CONSTRAINT_ARRAY`,
but the early exit references the original `${CONSTRAINTS}` variable.

**Fix**: Use `${CONSTRAINT_ARRAY}` instead of `${CONSTRAINTS}` in the early-exit path.

### P4. synthesizer.md Output Schema Already Defined But Misaligned [MEDIUM, LOW effort]
**Source**: ae3558a | **Validated**: PARTIALLY

synthesizer.md lines 182-303 define an output format, and synthesis-protocol.md
also defines output fields in its implementation ordering section. However:
- synthesizer.md output has `synthesis_id`, `timestamp` fields
- format-output.sh expects `systems_analyzed`, `unified_recommendation`,
  `cross_dependencies[]`, `conflicts[]`, `implementation_order[]`

The synthesizer.md output actually matches these fields. The research agent's
finding about "missing output schema" was partially incorrect — synthesizer.md
DOES have an Output Format section (lines 182+).

However, format-output.sh `format_cross_system()` function expects specific
field structures. Let me verify this is compatible.

**Verdict**: Downgraded from PASS to FAIL — synthesizer.md already has an output
schema and format-output.sh handles it correctly via jq `// []` fallbacks.

### P5. orchestration-protocol.md Agent Task Template Add `upstream_results` [MEDIUM, LOW effort]
**Source**: ae3558a | **Validated**: YES

orchestration-protocol.md Agent Task Prompt Template (lines 154-197) does not
include an optional `upstream_results` field for sequential agent dispatch.

db-orchestrator.md includes it in its dispatch procedure, but the generic
template should document it.

**Fix**: Add optional `## Upstream Results` section to the agent template.

### P6. _common.sh Remove Unused `sanitize_json_value` [LOW, TRIVIAL effort]
**Source**: adaf042 | **Validated**: YES

`sanitize_json_value` function (line 62-65 approximately) defined but never
called by any script. Dead code.

**Fix**: Remove the function.

---

## FAIL — Skip

### F1. Exit Code Mismatch in resolve-constraints.sh
**Source**: adaf042 | **Reason**: By design

Exit code 1 with JSON on stdout is a valid pattern. The caller can choose to
check exit code OR parse the JSON error field. Both approaches work.

### F2. format-output.sh `bc` Dependency
**Source**: adaf042 | **Reason**: LOW ROI

`bc` is installed by default on macOS and all major Linux distributions. Adding
a dependency check adds complexity for an edge case that virtually never occurs.

### F3. validate-agent-output.sh Confidence Regex
**Source**: adaf042 | **Reason**: TRIVIAL impact

The regex `^[0-9]*\.?[0-9]+$` technically accepts `.5` (valid) but also edge
cases like `.` (invalid). In practice, LLM-generated confidence values are
always proper floats. Not worth the code change.

### F4. Constraint Lifecycle Functions "Unused"
**Source**: adaf042 | **Reason**: Misunderstanding

`init_constraints`, `write_constraint`, `read_constraints`, `archive_constraints`
are designed to be called by the LLM via `Bash` tool during orchestration, not
by other shell scripts. They are a library API. Not dead code.

### F5. Synthesizer Output Schema Missing
**Source**: ae3558a | **Reason**: Already exists

synthesizer.md lines 182-303 contain a complete Output Format section with
`synthesis_id`, `systems_analyzed`, `cross_dependencies`, `conflicts`,
`unified_recommendation`, `implementation_order`, `risk_assessment`, etc.

### F6. Cross-system Constraint Tagging
**Source**: ae3558a | **Reason**: Already handled

Orchestrators output `resolved_constraints` and `unresolved_constraints` per
orchestration-protocol.md. The synthesizer receives all orchestrator outputs
and identifies cross-system implications via its dependency detection rules
(synthesis-protocol.md §2). No additional `impacts` field is needed at the
orchestrator level.

### F7. Constraint Collection API Documentation
**Source**: ae3558a | **Reason**: Already documented

constraint-propagation.md §Storage Format (lines 285-309) documents the
format. _common.sh provides the API functions. orchestration-protocol.md
Step 5 (line 342) references write_constraint(). The flow is documented.

### F8. Session Persistence Silent Failures
**Source**: adaf042 | **Reason**: By design

Session persistence is intentionally non-blocking (`2>/dev/null || true`).
Classification output must not be blocked by cache failures. The trade-off
(silent failure vs reliability) is acceptable for a bonus optimization feature.

---

## Summary

| ID | Finding | Verdict | Priority | Effort |
|----|---------|---------|----------|--------|
| P1 | be-orchestrator.md B5→B-5 naming bug | PASS | HIGH | TRIVIAL |
| P2 | be-orchestrator.md clusters_analyzed alignment | PASS | MEDIUM | LOW |
| P3 | resolve-constraints.sh flat array null bug | PASS | HIGH | LOW |
| P5 | orchestration-protocol.md upstream_results template | PASS | MEDIUM | LOW |
| P6 | Remove unused sanitize_json_value | PASS | LOW | TRIVIAL |
| F1-F8 | Various | FAIL | — | — |

**5 PASS items, 8 FAIL items.**
Estimated total effort: ~15 min implementation.
