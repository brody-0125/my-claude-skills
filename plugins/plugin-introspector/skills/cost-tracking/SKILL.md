---
name: cost-tracking
description: >-
  Model-specific pricing tables and cost calculation utilities
  for Claude API usage tracking and budget management.
user-invocable: false
---

# Cost Tracking — Model Pricing & Calculation

> Provides pricing data and calculation methods for API cost estimation.

## Model Pricing (per 1M tokens, USD)

| Model | Input | Output | Cache Write (5m) | Cache Read |
|-------|-------|--------|------------------|------------|
| claude-opus-4-6 | $5.00 | $25.00 | $6.25 | $0.50 |
| claude-sonnet-4-5 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-haiku-4-5 | $1.00 | $5.00 | $1.25 | $0.10 |

*Prices as of 2026-02. Source: [platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing). Update when pricing changes.*

## Cost Calculation

### Per-Request Cost

```
cost = (input_tokens × input_price / 1_000_000) +
       (output_tokens × output_price / 1_000_000) +
       (cache_write_tokens × cache_write_price / 1_000_000) +
       (cache_read_tokens × cache_read_price / 1_000_000)
```

### Session Cost Estimation

When actual API token counts are unavailable, use estimates:

```
estimated_input_tokens = sum(tool_input_chars) / 4
estimated_output_tokens = sum(tool_result_chars) / 4
estimated_cost = estimated_input_tokens × input_price / 1_000_000 +
                 estimated_output_tokens × output_price / 1_000_000
```

**Accuracy note**: chars/4 estimation has ±20% error. Actual API usage data (from api_traces.jsonl) provides exact costs when available.

## Budget Thresholds

| Level | Threshold | Action |
|-------|-----------|--------|
| INFO | >$0.50/session | Log to stats |
| WARNING | >$2.00/session | Alert (MEDIUM severity) |
| CRITICAL | >$10.00/session | Alert (HIGH severity) |

## Cost Efficiency Metrics

| Metric | Formula | Target |
|--------|---------|--------|
| Cost per tool call | session_cost / tool_calls | <$0.03 |
| Cost per productive call | session_cost / productive_calls | <$0.05 |
| Input/Output ratio | input_tokens / output_tokens | 3:1 to 6:1 (normal range) |

## Improvement ROI Scoring

Formula for prioritizing improvement proposals:

```
ROI_score = (Impact × Confidence) / (Effort × Risk)
```

### Impact (1-10)

```
token_impact = min(tokens_saved_per_session / 1000, 10)
quality_impact = quality_score_improvement_est × 3
Impact = max(token_impact, quality_impact)
```

### Confidence (0.0-1.0)

```
base = 0.3 if sessions < 3, 0.6 if sessions 3-7, 0.85 if sessions >= 8
corroboration_bonus = (confirming_agents - 1) × 0.1
Confidence = min(base + corroboration_bonus, 1.0)
```

### Effort (1-5)

| Level | Description |
|-------|-------------|
| 1 | Single line addition/change |
| 2 | Multi-line section modification |
| 3 | New section or procedure step |
| 4 | Structural change across multiple sections |
| 5 | Component rewrite or new component |

### Risk (1-5)

| Level | Description |
|-------|-------------|
| 1 | Additive only (no existing behavior changed) |
| 2 | Minor behavior modification in non-critical path |
| 3 | Critical path modification with clear rollback |
| 4 | Cross-component change with interaction risk |
| 5 | Core algorithm/flow change |

### Priority Mapping

```
ROI >= 2.0 → CRITICAL
ROI >= 1.0 → HIGH
ROI >= 0.5 → MEDIUM
ROI <  0.5 → LOW
```
