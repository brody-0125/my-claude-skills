---
name: analysis-patterns
description: >-
  Reusable analysis patterns and heuristics for plugin execution data.
  Provides standardized methods for pattern detection, anomaly scoring,
  and improvement signal extraction.
user-invocable: false
---

# Analysis Patterns — Reusable Heuristics

> Standardized analysis methods used by multiple agents.

## Tool Sequence Patterns

### Productive Sequences (high correlation with quality score ≥4)

| Pattern | Description | Expected Token Cost |
|---------|-------------|-------------------|
| `Read→Edit→Bash(pass)` | Read file, edit, verify | ~1500 tokens |
| `Glob→Read→Edit` | Find file, read, edit | ~1800 tokens |
| `Read→Task(sub)→Edit` | Read, delegate, apply | ~2500 tokens |

### Anti-Patterns (high correlation with quality score ≤3)

| Pattern | Description | Token Waste |
|---------|-------------|------------|
| `Read→Read→Read(same)` | Repeated reads of same file | ~1000 tokens/repeat |
| `Bash(fail)→Bash(fail)→Edit` | Build-before-edit | ~800 tokens wasted |
| `Edit→Bash(fail)→Edit→Bash(fail)` | Edit-test loop without reading error | ~1500 tokens/cycle |

## Statistical Methods

### Z-Score Calculation

```
z = (x - μ) / σ
Threshold: |z| > 2.0 → anomaly
Minimum data points: 5 (for reliable σ)
```

### Moving Average

```
MA(n) = sum(last_n_values) / n
Window: 5 sessions (default)
Alert if: current > MA × 1.5
```

### Efficiency Ratio

```
efficiency = productive_calls / total_calls
productive_call = call that contributed to final output (no retry, no revert)
Target: ≥ 0.85
```

## Token Estimation Baselines

Expected token usage per tool (for waste detection):

| Tool | Expected Range | Flag If |
|------|---------------|---------|
| Read | 200-1500 | >2000 (large file, use offset) |
| Edit | 100-500 | >800 (complex edit, consider split) |
| Write | 200-2000 | >3000 (generated file too large) |
| Bash | 50-500 | >1000 (verbose output, use --quiet) |
| Glob | 50-200 | >500 (too many matches) |
| Grep | 50-300 | >800 (broad search pattern) |
| Task | 500-5000 | >8000 (sub-agent context explosion) |

## Plugin Phase Patterns

Phase detection and per-plugin baselines are loaded dynamically from plugin profiles:
`~/.claude/plugin-introspector/plugin-profiles/{plugin}/profile.json`

When baselines unavailable (< 5 sessions), use universal defaults:
- Entry phase: 5-15% of session tokens
- Middle phases: 35-60% combined
- Exit phase: 15-30% of session tokens

> Phase-Generic Anti-Patterns (PG-001~PG-007) are defined in
> [improvement-pipeline.md](../plugin-introspector/resources/improvement-pipeline.md) Layer 2.

## Improvement Signal Extraction

### From Quality Evaluator

Field names match quality-evaluator.md `improvement_signals[]` output:

```
IF dimension.score ≤ 3:
  signal = {
    dimension: dimension.name,
    score: dimension.score,
    score_gap: 5 - dimension.score,
    what: "description of the issue",
    root_cause: "underlying cause",
    quantified_impact: {tokens, cost_usd, percentage_of_session},
    trace_evidence: ["trace_id: description", ...],
    suggested_change: {target_file, change_type, description},
    priority: score_gap × dimension.weight
  }
```

### From Token Optimizer

```
IF waste_source.tokens_wasted > total_tokens × 0.05:
  signal = {
    type: waste_source.type,
    impact: waste_source.tokens_wasted,
    priority: impact / total_tokens
  }
```

### From Anomaly Detector

```
IF alert.severity == "HIGH":
  signal = {
    type: alert.type,
    recurrence: count(similar_alerts_in_history),
    priority: recurrence > 2 ? "CRITICAL" : "HIGH"
  }
```
