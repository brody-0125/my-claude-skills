# Confidence Calibration Rubric

> A shared rubric that micro-agents use when computing `confidence` scores.
> The orchestrator references this document when executing Phase 2 agents.

---

## 5-Factor Scoring Model

All agents determine confidence by evaluating the following 5 axes.

| # | Factor | Description | Deduction Criteria |
|---|--------|-------------|-------------------|
| 1 | **Input Completeness** | Ratio of required constraints provided | Less than 50% provided → −0.20 |
| 2 | **Specificity** | Degree to which analysis is specialized to query context rather than generic | General statements without specific engine/version/metrics → −0.15 |
| 3 | **Evidence Grounding** | Degree to which recommendations are grounded in references/metrics/benchmarks | Recommendations without evidence → −0.15 |
| 4 | **Trade-off Coverage** | Degree to which alternatives and trade-offs are documented | trade_offs empty or contains only 1 item → −0.10 |
| 5 | **Assumption Count** | Number of explicitly stated assumptions | 3 or more assumptions → −0.10 |

---

## Scoring Procedure

```
base = 0.90  (when all factors are met)
confidence = max(0.0, base - Σ(applicable deductions))
```

### Floor Rules

| Condition | Upper Bound |
|-----------|------------|
| `missing_info` present | must be < 0.50 |
| 1–2 assumptions | maximum 0.80 |
| 3 or more assumptions | maximum 0.70 |

### Scoring Examples

```
Example 1: All inputs sufficient, benchmark evidence present, 3 trade-offs, 0 assumptions
  → 0.90 - 0 = 0.90

Example 2: 80% of inputs obtained, some generic statements included (-0.15), 2 assumptions
  → 0.90 - 0.15 = 0.75, apply assumption floor → min(0.75, 0.80) = 0.75

Example 3: Less than 40% of inputs (-0.20), insufficient evidence (-0.15), missing_info present
  → 0.90 - 0.20 - 0.15 = 0.55, apply missing_info floor → min(0.55, 0.49) = 0.49
```

---

## Score Range Interpretation

Aligned with `audit-analysis.sh` gating thresholds.

| Range | Meaning | Downstream Handling |
|-------|---------|-------------------|
| **0.85–0.90** | Sufficient inputs, specific analysis, evidence grounded | PASS |
| **0.70–0.84** | Most inputs obtained, some assumptions present | PASS |
| **0.50–0.69** | Major inputs missing but reasonable inference possible | WARN — pass with warning |
| **0.30–0.49** | Critical information absent, `missing_info` required | RETRY — redispatch once |
| **< 0.30** | Analysis not feasible, fallback only | REJECT — orchestrator fallback |

---

## Adjustment Rules

| Rule | Description |
|------|------------|
| **> 0.90 Permission Conditions** | `constraints`, `trade_offs`, `rationale` must all be substantive (non-empty and specific) |
| **== 1.0 Forbidden** | Cache hits only — agents must not directly compute 1.0 |
| **≥ 0.90 + Low Signal** | `audit-analysis.sh` issues CALIBRATION warning (existing behavior) |

---

## Threshold Context Map

시스템 내 3개 confidence 임계값 계층의 관계와 목적을 명시한다.

| 계층 | 임계값 | 위치 | 목적 |
|------|--------|------|------|
| **분류 (Classification)** | 0.85 | `classify-query.sh` → SKILL.md Phase 0 | Fast-path 분류 신뢰도. 0.85 미만이면 LLM 검증 트리거 |
| **에이전트 산출 (Agent Base)** | 0.90 | 이 문서 § Scoring Procedure | 에이전트가 모든 5-factor를 충족 시 부여하는 기본 confidence 점수 |
| **게이팅 (Quality Gate)** | 0.70 | `audit-analysis.sh confidence` → analysis-audit-protocol.md | Phase 2.5 감사 통과 최소 기준. 0.70 미만이면 WARN/RETRY/REJECT |

**관계**: 에이전트 base(0.90)에서 감점 후 산출된 최종 confidence가 게이팅 임계값(0.70)과 비교된다. 분류 임계값(0.85)은 독립적으로 Phase 0에서만 사용된다.
