# Analysis Audit Protocol

> 3개 감사 서브페이즈(Phase 2.5, 3.5, 4.5)의 전체 프로토콜 정의.
> Phase 2.5 진입 시 1회 로딩 → Phase 3.5, 4.5에서 재사용.

---

## Audit Tier 결정

Tier는 분류 결과와 에이전트 수에 따라 자동 결정된다. `scripts/audit-analysis.sh tier` 명령으로 결정론적 판별.

| Tier | 조건 | Phase 2.5 | Phase 3.5 | Phase 4.5 | 추가 토큰 |
|------|------|-----------|-----------|-----------|----------|
| **LIGHT** | Single-domain, 1 agent, shallow | Confidence gating만 | Skip | Skip | +0.3K |
| **STANDARD** | Multi-domain OR 2+ agents (기본) | 완전성 + Confidence + 실행가능성 | 스키마 계약 검증 | Skip | +1.5K |
| **THOROUGH** | Cross-system OR deep(4+ agents) OR 보안 키워드 | 전체 + 동적 확장 + Audit Agent | 전체 + Priority 일관성 | 전체 | +3.5K |

### 자동 에스컬레이션 (상향만, 하향 없음)

```
IF confidence < 0.50인 agent_results가 2개 이상 → LIGHT → STANDARD
IF 예상 외 cross-system constraint 발견 → STANDARD → THOROUGH
IF agent 출력에서 보안 키워드 탐지 (auth, encrypt, credential, vulnerability) → THOROUGH 즉시
```

---

## Phase 2.5 — Analysis Quality Gate

Phase 2 (Agent Execution) 완료 직후, Phase 3 (Constraint Resolution) 진입 전에 실행.

### Step 1: Confidence Gating (모든 Tier)

`scripts/audit-analysis.sh confidence <agent-output>` 실행.

| Confidence | Action | 코드 |
|------------|--------|------|
| >= 0.70 | PASS — 정상 처리 | — |
| 0.50 - 0.69 | PASS + 출력에 "Moderate confidence" 경고 추가 | EW-AUD-001 |
| 0.30 - 0.49 | 단순화된 프롬프트로 1회 재dispatch (reference 제거, query+constraints만). 재dispatch 후에도 < 0.50이면 orchestrator fallback 교체 | EW-AUD-002 |
| < 0.30 | 즉시 reject, orchestrator fallback 교체 (재dispatch 없음) | EW-AUD-003 |

각 `agent_results[]` 항목에 대해 개별 적용. 여러 에이전트가 동시에 낮은 confidence를 보이면 에스컬레이션 규칙 적용.

### Step 2: Completeness Audit (STANDARD+, 프로토콜 기반)

Gateway Router 또는 Orchestrator가 LLM 판단으로 수행하는 6-point 체크리스트:

1. **맥락 반영**: 분석이 사용자 쿼리의 구체적 맥락을 반영하는가 (generic 아닌가)
2. **정량적 데이터**: 정량적 데이터 포함 여부 (해당될 경우 — 수치, 벤치마크, 비율 등)
3. **Trade-off 문서화**: 최소 2개 옵션 비교 (`trade_offs` 필드 확인)
4. **Constraint 선언**: Multi-domain인데 constraints 0개면 의심 — 경고 추가 (EW-AUD-010)
5. **Actionable 추천**: 추천이 모호하지 않고 실행 가능한가
6. **컨텍스트 인용**: 사용자 쿼리의 핵심 용어를 분석에서 참조하는가

> 검사 주체: LLM (Gateway Router/Orchestrator). `validate-agent-output.sh`의 `quality_score`를 보조 지표로 활용.

### Step 3: Feasibility Check (STANDARD+, 프로토콜 기반)

- 추천안이 `constraints_used`에 있는 사용자 환경 제약을 참조하는지 확인
- 비현실적 추천 플래그:
  - 단일 서버 환경에서 multi-master 추천
  - 소규모 DB에서 sharding 추천
  - 환경 제약 없이 특정 인프라 가정

실행가능성 문제 발견 시 EW-AUD-005 경고 + 대안 제시 요청.

### Step 4: Dynamic Issue Expansion (THOROUGH만, Audit Agent dispatch)

`agents/audit-reviewer.md`를 dispatch하여 수행.

```
각 agent_result의 analysis + recommendation에서 키워드 추출
  → _common.sh의 detect_db_domain / detect_be_cluster 재활용
  → 현재 분류에 없는 도메인 매칭 시 expansion_candidate 추가

expansion_candidates가 있으면:
  IF 현재 토큰 사용량 > budget × 0.80 → 확장 억제 (EW-AUD-004 로그)
  ELSE → priority_matrix_level 기준 상위 최대 2개 도메인에 추가 에이전트 dispatch
  → 확장 결과에 expansion_triggered: true 마킹
```

---

## Phase 3.5 — Contract Enforcement Gate

Phase 3 (Constraint Resolution) 완료 직후, Phase 4 (Synthesis) 진입 전에 실행.
STANDARD 이상에서 활성화. LIGHT에서는 skip.

### Step 1: Schema Contract Validation (STANDARD+)

`scripts/audit-analysis.sh orchestrator <output>` 실행. 각 orchestrator 출력 검증:

| 필드 | 필수 수준 | 누락 시 대응 |
|------|----------|-------------|
| `system` | CRITICAL | 결과 reject |
| `status` | CRITICAL | `"partial"`로 기본값 + 경고 |
| `guidance` | Required | 첫 번째 `recommendations[0].title`로 대체 |
| `recommendations` | Required | 빈 배열 + 경고 |
| `resolved_constraints` | Required | 빈 배열 |
| `unresolved_constraints` | Required | 빈 배열 |
| `metadata.confidence` | Required | `0.5`로 기본값 + 경고 |

### Step 2: Priority Consistency Check (THOROUGH만)

모든 intra-system conflict resolution이 `priority-matrix.md`의 규칙을 따르는지 검증.

DB-specific 규칙과 범용 matrix의 매핑:

| DB 규칙 (constraint-propagation.md) | Priority Matrix (priority-matrix.md) |
|------|------|
| Correctness (Domain C) | Data Integrity (Level 5) |
| Durability (Domain E: WAL, checkpoint, flush) | Data Integrity (Level 5) |
| Performance (Domain A, B; Domain E: buffer/I/O tuning) | Performance (Level 2) |
| Scalability (Domain F) | Availability (Level 3) |
| Simplicity (Domain D) | Convenience (Level 1) |

검증 방법:
1. `resolved_constraints`에서 conflict resolution이 적용된 항목 추출
2. 각 resolution의 rationale이 위 매핑과 일치하는지 확인
3. 불일치 발견 시 EW-AUD-006 경고

### Step 3: Constraint Forwarding Completeness (THOROUGH만)

`scripts/audit-analysis.sh orchestrator`가 자동 검출하는 항목:

- `impacts` 배열이 다른 시스템을 가리키는 resolved constraint가 `unresolved_constraints`에도 포함되었는지 확인
- 누락 시 자동 추가 + EW-AUD-006 경고 로그

---

## Phase 4.5 — Synthesis Validation Gate

Cross-system 패턴에서만 활성화. THOROUGH tier 전용.
Phase 4 (Synthesis) 완료 직후, Phase 5 (Output Formatting) 진입 전에 실행.

### Step 1: Coverage Check

`scripts/audit-analysis.sh synthesis <output>` 실행.

- `unified_recommendation`이 참여한 모든 시스템(`systems_analyzed`)의 분석을 반영하는지 확인
- 특정 시스템 결과가 무시되었다면 EW-AUD-007 경고

### Step 2: Ordering Validation

- `implementation_order`의 `depends_on`이 실제 존재하는 phase를 참조하는지 확인
- `cross_dependencies`와의 일관성 위상정렬 검증
- 위반 시 EW-AUD-008 에러

### Step 3: Risk-Rollback Completeness

- `risk: "high"`인 페이즈에 `rollback` 전략이 정의되었는지 확인
- 누락 시 EW-AUD-009 경고

### Step 4: Confidence Floor Enforcement

- `confidence_assessment.overall`이 `"low"`이면 출력에 명시적 caveat 추가
- stub orchestrator 결과 포함 시 영향 범위 명시

---

## 토큰 Budget 관리

### Audit 추가분

| 패턴 | 기존 예산 | Audit 추가 | 새 예산 |
|------|----------|-----------|---------|
| Shallow (1 agent) | ~3.5K | +0.3K (LIGHT) | ~3.8K |
| Analysis (1-4 agents) | ~6K | +1.5K (STANDARD) | ~7.5K |
| Full pipeline (6-10) | ~12K | +1.5K (STANDARD) | ~13.5K |
| Cross-system (3-6) | ~15K | +3.5K (THOROUGH) | ~18.5K |
| Cross-system (pruning) | ~10K | +3.5K (THOROUGH) | ~13.5K |

### Budget 절약 전략

1. 이 문서(`analysis-audit-protocol.md`)는 Phase 2.5에서 1회 로딩 → 3.5, 4.5에서 재사용 (재로딩 없음)
2. `audit-analysis.sh`는 jq로 결정론적 검사 수행 → LLM 토큰 소비 0
3. 토큰 압박 > 80%: LIGHT 항목 skip, confidence gating만 유지
4. 토큰 압박 > 90%: 모든 audit skip, 직접 Phase 5로 전환

---

## 스크립트 참조

| 스크립트 | 용도 | Phase |
|---------|------|-------|
| `audit-analysis.sh confidence` | Confidence gating 판정 | 2.5 |
| `audit-analysis.sh orchestrator` | 스키마 계약 + forwarding 검증 | 3.5 |
| `audit-analysis.sh synthesis` | 합성 정합성 검증 | 4.5 |
| `audit-analysis.sh tier` | Tier 자동 결정 | 2.5 진입 전 |
| `validate-agent-output.sh` | quality_score 보조 지표 | 2.5 |

---

*이 프로토콜은 Phase 2.5 진입 시 로딩되며, Phase 3.5 및 4.5에서 재사용된다.*
