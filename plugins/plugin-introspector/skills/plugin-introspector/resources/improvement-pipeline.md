# Improvement Pipeline — Enhanced RETRIEVE-JUDGE-DISTILL-CONSOLIDATE

> Detailed procedure for the improvement-generator agent.
> Agent definition references this resource for full pipeline specification.

## 1. RETRIEVE

### 1a. Current Session Data

- Collect analysis findings from upstream agents:
  - workflow-analyzer → `recommendations[]`
  - token-optimizer → `waste_sources[]`, `optimization_suggestions[]`
  - quality-evaluator → `improvement_signals[]`
  - context-auditor → `compression_opportunities[]` (when available)
  - anomaly-detector → `alerts[]` with severity HIGH (when available)
- Load target plugin component files (per orchestration-protocol file selection)
- Load meta-rules constraints

### 1b. Cross-Session Context

- Load `evaluation_history.jsonl` (last 20 records)
- Load `improvement_log.jsonl` (all records for target plugin)

Compute:
- **Score trend**: weighted_score 5-session moving average direction (improving/declining/stable)
- **Regression check**: any applied improvement with `status == "regressed"`?
- **Effective improvements**: entries where `status == "validated"` — note their change_type
- **Recurring waste**: waste_sources appearing in >50% of recent evaluation_history records

### 1c. Plugin Profile & Patterns

When target_plugin is known:
1. Load `plugin-profiles/{plugin}/profile.json` → workflow type, phases
2. Load `plugin-profiles/{plugin}/phase-baselines.json` → quantified phase expectations
3. Load `plugin-profiles/{plugin}/learned-patterns.jsonl` → plugin-specific patterns

### 1d. Cross-Reference Findings

Group findings from all upstream agents by target (file path, phase, or tool):

```
For each pair of findings from different agents:
  if they reference the same file, phase, or tool:
    → Merge as single root cause with combined impact
    → corroboration_count = number of agents confirming
    → Combined confidence: base + (corroboration_count - 1) × 0.1
```

Flag contradictions: e.g., workflow-analyzer flags "phase too long" but quality-evaluator scores that dimension 5/5 → classify as "high-cost but high-value", adjust recommendation.

---

## 2. JUDGE

### 2a. ROI Scoring

For each finding, compute ROI score per [cost-tracking ROI formula](../../cost-tracking/SKILL.md) (Impact, Confidence, Effort, Risk → `ROI = (Impact × Confidence) / (Effort × Risk)`).

Filter: discard findings with ROI < 0.3

### 2b. Historical Validation

For each candidate finding:
1. Check improvement_log for similar past proposals (match by `target_file` + `change_type`)
2. If similar proposal was `"validated"`: boost confidence +0.2
3. If similar proposal was `"regressed"`: reduce confidence -0.3, add risk warning
4. If this is a recurring waste pattern (>50% of sessions): boost impact +2

Track effective improvement types:
- Compute `effectiveness[change_type] = count(validated) / count(applied)`
- Prefer change_types with effectiveness > 0.7
- Flag change_types with effectiveness < 0.3

### 2c. Evidence Threshold

| Analysis Type | Minimum Evidence |
|---------------|-----------------|
| Single-session | ≥ 1 data point with trace reference |
| Cross-session | ≥ 3 sessions with consistent pattern |
| Learned pattern | ≥ 2 sessions + ≥ 3 occurrences |

---

## 3. DISTILL

### 3a. Root Cause Extraction

For each finding passing JUDGE:
- Extract root cause from specific instance
- Abstract to general pattern
- Formulate concrete change addressing the root cause

### 3b. Multi-Layer Pattern Matching

For each finding, match against patterns in priority order:

**Layer 1 — Universal Patterns** (always check):

| ID | Symptom | Template |
|----|---------|----------|
| U-001 | Same file Read ≥3 times | "Cache {file} after first Read" |
| U-002 | Bash(fail)→Bash(fail) same command | "Read error output before retrying" |
| U-003 | Read:Edit ratio > 4:1 | "Narrow search with Glob/Grep before Read" |
| U-004 | Task agent > 8000 tokens | "Reduce agent context or split task" |
| U-005 | Edit→Bash(fail) cycle ≥2 | "Read error fully before next Edit attempt" |

**Layer 2 — Phase-Generic Patterns** (if `profile.workflow.type == "phased"`):

| ID | Symptom | Template |
|----|---------|----------|
| PG-001 | Entry phase > baseline × 1.5 | "Check if {phase} results can be cached across sessions" |
| PG-002 | Exit phase > baseline × 1.5 | "Check convergence in {phase}: review error handling" |
| PG-003 | Phase re-entry (backward transition) | "Context loss at {phase_j}→{phase_i}: add carry-forward" |
| PG-004 | Optional phase skipped for complex inputs | "Consider triggering {phase} for complex inputs" |
| PG-005 | Resource re-read across phases | "Retain {resource} from {source_phase}" |
| PG-006 | Non-optional phase with 0 traces | "Phase {phase} skipped — verify correctness" |
| PG-007 | Loop phase iterations > 3 | "Convergence issue in {phase}: review error diagnosis" |

**Layer 3 — Learned Patterns** (if `learned-patterns.jsonl` exists):
- Match finding against stored patterns by symptom type + phase_context
- Exact match: apply `improvement_template`, confidence +0.15
- If pattern `effectiveness == "regressed"`: suppress proposal

Tag each proposal with `pattern_layer` (L1/L2/L3) and `pattern_id`.

---

## 4. CONSOLIDATE

### 4a. Grouping

- Group related changes by target file
- Merge proposals targeting the same file section
- Resolve conflicts: higher ROI wins, note the discarded alternative

### 4b. Meta-Rules Validation

Validate all proposals against meta-rules:
- Agent description < 1000 tokens after modification
- Skill content < 500 tokens after modification
- Explicit trigger conditions preserved
- At least 1 example, no more than 2

### 4c. Output Construction

For each proposal, produce:

```json
{
  "id": "IMP-001",
  "roi": {
    "score": 2.13,
    "impact": 6,
    "confidence": 0.85,
    "effort": 1,
    "risk": 2,
    "breakdown": "Impact: 2000 tokens/session = 6, Confidence: 8 sessions = 0.85, Effort: 1-line add = 1, Risk: additive = 2"
  },
  "priority": "CRITICAL",
  "target_file": "agents/workflow-analyzer.md",
  "change_type": "modify",
  "pattern": {"layer": "L2", "id": "PG-005"},
  "description": "Add carry-forward instruction for plan-protocol.md at Plan→Implement transition",
  "evidence": {
    "sources": [
      {"agent": "workflow-analyzer", "finding": "Plan→Implement re-reads plan-protocol.md"},
      {"agent": "token-optimizer", "finding": "plan-protocol.md read 3.2x/session, 625 tokens each"}
    ],
    "quantified_impact": {
      "tokens_saved_per_session": 2000,
      "cost_saved_per_session_usd": 0.006,
      "quality_score_improvement_est": 0.3
    },
    "statistical_confidence": {
      "data_points": 8,
      "sessions_analyzed": 8,
      "pattern_consistency": 0.85
    },
    "counterfactual": "If plan-protocol.md cached at Plan→Implement transition, 3.2 redundant reads × 625 tokens = 2000 tokens saved per session"
  },
  "diff": "--- a/agents/workflow-analyzer.md\n+++ b/agents/workflow-analyzer.md\n...",
  "meta_rules_check": {"passed": true, "token_count": 850, "violations": []}
}
```

### Summary Output

```json
{
  "summary": {
    "total_proposals": 3,
    "by_priority": {"CRITICAL": 1, "HIGH": 1, "MEDIUM": 1},
    "total_tokens_savings_est": 5000,
    "total_cost_savings_est_usd": 0.015,
    "score_trend": "stable",
    "historical_context": "2 past improvements validated, 0 regressed"
  }
}
```
