# Engineering-Workflow 심층 리서치 리포트

> 워크플로우 · 에이전트 · 디자인 패턴 · 컨텍스트 · 토큰 설계 5축 감사 결과
> 감사일: 2026-02-12

---

## 현재 상태 요약

| 항목 | 수치 |
|------|------|
| 전체 코드베이스 | ~22,300줄 (est. 44,600 토큰) |
| 마이크로 에이전트 | 35개 (DB 17 + BE 18) |
| 오케스트레이터 | 4개 (DB ✓, BE ✓, IF stub, SE stub) |
| 신시사이저 | 1개 |
| 리소스 프로토콜 | 7개 |
| 레퍼런스 파일 | 30개 (DB 17 + BE 11 + shared 2) |
| 스크립트 | 5개 |

---

## CRITICAL 발견사항 (즉시 수정 필요)

### C-1. SKILL.md DB 에이전트 경로 불일치

**문제**: SKILL.md(568-573행)가 참조하는 DB 에이전트 파일명이 실제 파일과 완전히 다름.

| SKILL.md 참조 | 실제 파일 |
|--------------|----------|
| `agents/db/storage-engine-agent.md` | `agents/db/a1-engine-selector.md`, `a2-compaction-strategist.md` |
| `agents/db/query-optimization-agent.md` | `agents/db/b1-index-architect.md`, `b2-*`, `b3-*` |
| `agents/db/schema-design-agent.md` | `agents/db/c1-isolation-advisor.md` ... |
| (6개 전체 불일치) | (17개 실제 파일) |

**영향**: Gateway Router가 SKILL.md 경로로 에이전트를 로드하면 file not found 발생. 모든 DB 크로스시스템 쿼리가 실패.

**수정**: SKILL.md의 에이전트 목록 테이블을 실제 파일명(a1-*, b1-* 등)으로 업데이트.

---

### C-2. 오케스트레이터↔신시사이저 스키마 불일치

**문제**: DB/BE 오케스트레이터 출력 스키마와 신시사이저 입력 스키마가 구조적으로 비호환.

**오케스트레이터 출력** (db-orchestrator.md):
```json
{"query": "...", "domains_analyzed": ["A"], "agents_dispatched": [...], "merged_recommendations": [...]}
```

**신시사이저 기대 입력** (synthesis-protocol.md):
```json
{"system": "DB", "status": "completed", "guidance": "...", "recommendations": [...]}
```

누락 필드: `system`, `status`, `guidance` — 신시사이저가 오케스트레이터 결과를 파싱할 수 없음.

**수정**: 오케스트레이터 출력 스키마에 `system`, `status`, `guidance` 필드 추가. 또는 신시사이저 입력 검증을 양쪽 스키마 호환으로 업데이트.

---

### C-3. 세션 히스토리 무한 성장

**문제**: `session-history.jsonl`이 append-only이며 TTL, 최대 크기, 정리 메커니즘이 없음.

| 쿼리 수 | 히스토리 크기 | 패턴 캐시 |
|---------|-------------|----------|
| 10 | ~3.5K 토큰 | ~1K |
| 100 | ~35K 토큰 | ~5K |
| 365일 | ~120K 토큰 | ~9K |

`constraints-archive/`도 "최근 20개 유지" 정책이 문서화만 되고 미구현.

**수정**: `_common.sh`에 cleanup 함수 3개 추가:
- `cleanup_session_history(max_entries=1000, max_age_days=30)`
- `evict_pattern_cache(max_entries=30, max_age_days=90)`
- `cleanup_constraints_archive(keep_count=20)`

---

### C-4. 크로스시스템 컨텍스트 누적 — 예산 초과

**문제**: 크로스시스템 쿼리(Pattern 3)에서 Phase별 컨텍스트가 정리 없이 누적되어 명시 예산의 127-164%에 도달.

```
Phase 0: SKILL.md               → 1.2K 토큰 (누적 1.2K)
Phase 1: 3 오케스트레이터        → +2.5K   (누적 3.7K)
Phase 2: 6-10 에이전트 + 레퍼런스 → +5.5K   (누적 9.2K)
Phase 3: constraint-propagation  → +0.6K   (누적 9.8K)
Phase 4: synthesizer             → +1.2K   (누적 11.0K)
Phase 5: 최종 출력               → +0.8K   (누적 11.8K)
                              명시 예산: 11K → 실제: 14-18K (27-64% 초과)
```

**수정**: Phase 간 컨텍스트 정리 메커니즘 설계 (아래 개선안 섹션 참조).

---

## HIGH 발견사항

### H-1. LLM 분류 폴백 미구현

**문제**: `routing-protocol.md`가 confidence < 0.85일 때 LLM 분류를 문서화하지만, `classify-query.sh`에는 LLM 호출 코드가 없음. 모호한 쿼리(0.50-0.84)가 검증 없이 라우팅됨.

**영향**: 2개 이상 시스템 매칭(confidence 0.60) 또는 단일 시스템 도메인 미특정(confidence 0.70)인 쿼리가 부정확하게 라우팅될 수 있음.

**수정 옵션**:
- Option A: `classify-query.sh`에 haiku 모델 LLM 호출 추가 (confidence < 0.85일 때)
- Option B: `routing-protocol.md`를 현실에 맞게 업데이트 (LLM 폴백은 향후 구현으로 문서화)

---

### H-2. IF/SE 오케스트레이터가 스텁

**문제**: 4도메인 시스템을 표방하지만 실제로는 DB/BE만 에이전트가 구현됨. IF/SE 쿼리는 키워드 기반 일반 가이던스만 반환하며 `confidence: "low"`.

**영향**: 크로스시스템 쿼리에서 IF/SE 결과가 포함되면 신시사이저가 저신뢰 결과를 혼합하여 전체 권장사항 품질이 저하됨.

**수정**: SKILL.md에 IF/SE 스텁 상태를 명시적으로 문서화. 크로스시스템 쿼리 시 스텁 시스템에 대한 경고 메시지 추가.

---

### H-3. 레퍼런스 로딩 전략 미이행

**문제**: `orchestration-protocol.md`가 정의한 3단계 전략(≤200줄: inline, 201-500줄: offset/limit, >500줄: grep+read)을 오케스트레이터가 무시하고 전체 파일을 인라인 로딩.

| 현재 (인라인) | 권장 (타겟 추출) | 절감 |
|-------------|---------------|------|
| 3 에이전트 × 600줄 = 3,600 토큰 | 3 × 200줄 = 1,200 토큰 | **67%** |

**수정**: 오케스트레이터에 레퍼런스 로딩 전략 구현 지시 추가. 또는 레퍼런스 파일을 에이전트별로 더 작게 분할.

---

### H-4. 크로스시스템 제약 충돌 누락 가능

**문제**: 각 오케스트레이터가 제약을 내부 해결한 후 신시사이저에 전달 → 시스템 간 암묵적 충돌이 필터링됨.

예: DB가 "LSM sorted key 필요" 선언, BE가 "off-heap caching 권장" — 각각 내부 해결되어 신시사이저가 충돌을 감지할 수 없음.

**수정**: 오케스트레이터가 내부 해결된 제약과 미해결 제약을 모두 신시사이저에 전달하도록 출력 스키마 확장.

---

### H-5. 통합 에러 분류 체계 부재

**문제**: `error-playbook.md`가 7개 에러 카테고리를 정의하지만 에러 코드 체계가 없음. 또한 재시도 정책이 모순:
- `error-playbook.md`: "실패 에이전트 자동 재시도 금지"
- `be-orchestration-protocol.md`: "실패 시 간소화 입력으로 1회 재시도"

**수정**: 에러 코드 체계 정의 + 재시도 정책 통일.

---

### H-6. 테스트 시나리오 및 검증 부재

**문제**: 전체 플러그인에 예제 쿼리, 예상 출력, 엔드투엔드 테스트 케이스가 없음. `validate-agent-output.sh`가 존재하지만 에이전트별 스키마 검증은 미구현.

**수정**: `tests/classification-scenarios.json` 생성 + `validate-agent-output.sh` 확장.

---

## MEDIUM 발견사항

### M-1. 충돌 해결 우선순위 매트릭스 충돌

| 문서 | 우선순위 규칙 |
|------|------------|
| `synthesis-protocol.md` | Data Integrity(5) > Security(4) > Availability(3) > Performance(2) > DX(1) |
| `constraint-propagation.md` | Consistency > Performance > Storage efficiency (DB 한정) |
| `error-playbook.md` | SE > DB > BE > IF (시스템 우선순위) |

3개 문서가 서로 다른 우선순위 규칙을 정의하며 어느 것이 적용되는지 불명확.

**수정**: 단일 `resources/priority-matrix.md` 파일로 통합하고 모든 문서가 이를 참조.

---

### M-2. BE Chain 3 "per step" 표기 모호

Chain 3 (Saga Design): `B-4 → B-2(per step) → R-3(per step) → T-1` — "per step"이 병렬 디스패치인지 순차 호출인지 미정의.

**수정**: 3-step saga 예시로 구체적 디스패치 순서 문서화.

---

### M-3. SKILL.md 도메인 명칭 불일치

| SKILL.md | db-orchestrator.md |
|----------|-------------------|
| Query Optimization | Index & Scan |
| Schema Design | Concurrency |
| Concurrency Control | I/O & Pages |

도메인 B-F의 설명이 두 문서 간 불일치.

**수정**: 통일 명칭 정의 후 양쪽 문서 업데이트.

---

### M-4. `resolve-constraints.sh` 의미적 충돌 감지 미구현

현재: `target == target AND value != value`만 감지. `semantic_overlap()`, `contradicts()`, `same_topic()`은 주석 수준의 의사코드.

**수정**: 최소한 `same_topic()` 구현 (관련 키워드 매핑 테이블 기반).

---

### M-5. 버전/변경로그 부재

`plugin.json`에 `1.0.0` 있으나 SKILL.md에 버전 필드 없음. 변경 이력이나 마이그레이션 가이드 없음.

**수정**: SKILL.md에 버전 필드 추가, `docs/CHANGELOG.md` 생성.

---

### M-6. 자매 스킬 위임 프로토콜 부재

`sub-kopring-engineer`(코드 컨벤션), `sub-test-engineer`(테스트 생성)과의 위임 인터페이스 미정의. BE T3(test-generator)와 `sub-test-engineer`가 중복 영역.

**수정**: 위임 트리거 조건과 인터페이스 스키마를 SKILL.md에 문서화.

---

### M-7. Hook 설계 불완전

`plugin.json`이 `PreToolUse`(시크릿 파일 차단)만 정의. 누락된 훅:
- `PostToolUse`: constraints.json 스키마 검증
- `Stop`: 세션 종료 시 제약 아카이브 + 패턴 캐시 프로모션

---

### M-8. DB 에이전트 NEVER 섹션 2개 누락

`a1-engine-selector`와 `d3-access-pattern-modeler`에 NEVER 섹션이 없음. BE 에이전트는 18/19개가 명시적 NEVER 보유.

---

## LOW / 긍정 발견사항

### 강점

| 항목 | 점수 | 비고 |
|------|------|------|
| 에이전트 템플릿 일관성 | 99% | 40개 에이전트 전체가 동일 구조 준수 |
| Input/Output 커플링 | 100% | 고아 데이터 없음, 피드백 루프(T4→T3) 완벽 |
| 모델 할당 적정성 | 100% | Sonnet 32개, Haiku 3개 — 전체 정당화 |
| NEVER 섹션 경계 | 98% | BE 18/19 명시적, DB a1·d3만 누락 |
| 에이전트 스코프 분리 | 100% | 유해한 중복 0건 |
| 체인 실행 설계 | 95% | 6개 체인 + 의존성 + 피드백 루프 |
| 키워드 단일 소스 | 100% | _common.sh에서만 정의, classify-query.sh는 함수 호출 |
| DB 레퍼런스 품질 | A | 17개 에이전트별 파일, 3-6 코드블록/100줄 |

---

## 개선안 설계

### Phase 1: 스키마 정합성 (CRITICAL)

#### 1-1. SKILL.md 에이전트 경로 수정

SKILL.md의 에이전트 목록 테이블을 실제 파일 구조로 교체:

```markdown
| Agent | Domain | Model |
|-------|--------|-------|
| [a1-engine-selector](./agents/db/a1-engine-selector.md) | A: Storage Engine | sonnet |
| [a2-compaction-strategist](./agents/db/a2-compaction-strategist.md) | A: Storage Engine | haiku |
| ... (17 DB agents + 18 BE agents) |
```

#### 1-2. 오케스트레이터 출력 스키마 통합

DB/BE 오케스트레이터 출력에 신시사이저 호환 필드 추가:

```json
{
  "system": "DB",
  "status": "completed",
  "guidance": "<merged_recommendations 요약>",
  "query": "...",
  "domains_analyzed": ["A", "B"],
  "recommendations": [...],
  "constraints_used": {...},
  "metadata": { "confidence": 0.82 }
}
```

#### 1-3. 제약 전파 개선

오케스트레이터 출력에 `resolved_constraints`와 `unresolved_constraints` 분리:

```json
{
  "resolved_constraints": [...],
  "unresolved_constraints": [...],
  "raw_agent_constraints": [...]
}
```

신시사이저가 `unresolved_constraints` + `raw_agent_constraints`에서 크로스시스템 충돌 감지.

---

### Phase 2: 컨텍스트 & 토큰 제어 (CRITICAL/HIGH)

#### 2-1. 세션 정리 메커니즘

```bash
# _common.sh에 추가
cleanup_session_history() {
  local max_entries="${1:-1000}"
  [ ! -f "${SESSION_HISTORY}" ] && return
  local count=$(wc -l < "${SESSION_HISTORY}")
  if [ "${count}" -gt "${max_entries}" ]; then
    local keep=$((max_entries * 80 / 100))
    tail -n "${keep}" "${SESSION_HISTORY}" > "${SESSION_HISTORY}.tmp"
    mv "${SESSION_HISTORY}.tmp" "${SESSION_HISTORY}"
  fi
}

evict_pattern_cache() {
  local max_age_days="${1:-90}"
  [ ! -f "${PATTERN_CACHE}" ] && return
  local cutoff
  cutoff=$(date -u -v-${max_age_days}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "${max_age_days} days ago" +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg cutoff "${cutoff}" \
    'to_entries | map(select(.value.last_used > $cutoff)) | from_entries' \
    "${PATTERN_CACHE}" > "${PATTERN_CACHE}.tmp"
  mv "${PATTERN_CACHE}.tmp" "${PATTERN_CACHE}"
}

cleanup_constraints_archive() {
  local keep="${1:-20}"
  [ ! -d "${CONSTRAINTS_ARCHIVE}" ] && return
  ls -1t "${CONSTRAINTS_ARCHIVE}"/constraints-*.json 2>/dev/null \
    | tail -n +$((keep + 1)) | xargs rm -f 2>/dev/null || true
}
```

#### 2-2. Phase 간 컨텍스트 정리 프로토콜

`orchestration-protocol.md`에 추가:

```
## Phase Transition Context Management

Phase 1 → Phase 2: 유지 (에이전트에 오케스트레이터 컨텍스트 필요)
Phase 2 → Phase 3: 에이전트 .md 정의 정리 (출력만 유지)
Phase 3 → Phase 4: 레퍼런스 정리 (제약 해결 결과만 유지)
Phase 4 → Phase 5: 오케스트레이터 원본 정리 (신시사이저 출력만 유지)

정리 규칙:
- 에이전트 출력 JSON: 항상 유지
- 에이전트 정의 .md: Phase 2 완료 후 정리 가능
- 레퍼런스 파일 내용: Phase 2 완료 후 정리 가능
- 오케스트레이터 .md: Phase 4 진입 시 정리 가능
- SKILL.md 코어 (100줄): 항상 유지
```

예상 절감:

| 시점 | 현재 | 개선 후 | 절감 |
|------|------|--------|------|
| Phase 4 진입 (크로스시스템) | 14-18K | 8-10K | 40-44% |

#### 2-3. SKILL.md 지연 로딩

SKILL.md를 5개 섹션으로 분리하여 Phase별 로딩:

| 섹션 | 줄 수 | 로딩 시점 |
|------|------|----------|
| 코어 (Role, 라우팅 테이블) | ~100 | Phase 0 (항상) |
| 실행 패턴, 깊이 모드 | ~120 | Phase 1 |
| 제약 전파 | ~50 | Phase 3 |
| 에러 핸들링 | ~25 | 에러 발생 시 |
| 세션, 상태 | ~35 | Phase 5 |

쿼리당 **~1K 토큰** 절감. 10쿼리 세션 기준 **~10K 토큰** 절감.

#### 2-4. 토큰 예산 재보정

실측 기반으로 SKILL.md 토큰 예산 테이블 업데이트:

| 패턴 | 현재 명시 | 실측 최소 | 실측 최대 | 권장 예산 |
|------|----------|----------|----------|----------|
| Shallow | ~2.5K | 2.7K | 3.4K | ~3.5K |
| Analysis | ~5K | 4.3K | 5.5K | ~6K |
| Implementation | ~7K | 6.2K | 7.2K | ~8K |
| Test Generation | ~8K | 7.8K | 9.5K | ~10K |
| Full Pipeline | ~10K | 9.2K | 11.8K | ~12K |
| Cross-system | ~11K | 13.2K | 18K | ~15K (정리 적용 시 ~10K) |

---

### Phase 3: 에러 & 테스트 (HIGH)

#### 3-1. 에러 코드 체계

```
EW-CLF-001: 분류 실패 (키워드 매칭 0건)
EW-CLF-002: 분류 모호 (confidence < 0.60)
EW-ORC-001: 오케스트레이터 타임아웃 (>60초)
EW-ORC-002: 에이전트 무효 JSON 반환
EW-ORC-003: 레퍼런스 파일 누락
EW-CST-001: 제약 충돌 (직접, 동일 target)
EW-CST-002: 제약 충돌 (의미적, 관련 target)
EW-SYN-001: 신시사이저 입력 스키마 불일치
EW-SYN-002: 의존성 사이클 감지
```

#### 3-2. 재시도 정책 통일

```
기본 정책: 자동 재시도 금지 (error-playbook.md 준수)
예외:
  - 네트워크 타임아웃 → 1회 재시도 (간소화 입력)
  - JSON 파싱 실패 → 1회 재시도 ("output JSON only" 지시 추가)
  - 스텁 오케스트레이터 → 재시도 불가 (즉시 stub 결과 반환)
```

#### 3-3. 테스트 시나리오 파일

```json
[
  {"query": "B-tree vs LSM storage engine", "expected": {"systems": ["DB"], "domains": ["A", "B"]}},
  {"query": "kubernetes deployment monitoring", "expected": {"systems": ["IF"]}},
  {"query": "OAuth JWT token management", "expected": {"systems": ["SE"]}},
  {"query": "implement saga with circuit breaker", "expected": {"systems": ["BE"], "be_clusters": ["B", "R"]}},
  {"query": "shard database and update connection pool", "expected": {"systems": ["DB", "BE"]}},
  {"query": "React component state management", "expected": {"systems": []}},
  {"query": "database transaction isolation level", "expected": {"systems": ["DB"], "domains": ["C"]}},
  {"query": "terraform infrastructure as code", "expected": {"systems": ["IF"]}},
  {"query": "RBAC authorization encryption", "expected": {"systems": ["SE"]}},
  {"query": "fixture monkey test generation coverage", "expected": {"systems": ["BE"], "be_clusters": ["T"]}}
]
```

---

### Phase 4: 구조 정합성 (MEDIUM)

#### 4-1. 우선순위 매트릭스 통합

단일 `resources/priority-matrix.md` 파일로 통합:

```markdown
## 범용 우선순위 (모든 충돌 해결에 적용)
1. Data Integrity (5) — 데이터 유실 비가역적
2. Security (4) — 취약점 복합적 확산
3. Availability (3) — 다운타임 즉각 비즈니스 영향
4. Performance (2) — 반복 개선 가능
5. Convenience/DX (1) — 중요하지만 부차적

## 시스템 간 동급 충돌 시 (위 순위 동일할 때)
SE > DB > BE > IF

## 사용자 오버라이드
constraints.json의 priority_overrides[]로 특정 쌍 재정의 가능
```

`synthesis-protocol.md`, `constraint-propagation.md`, `error-playbook.md` 모두 이 파일을 참조하도록 변경.

#### 4-2. 도메인 명칭 정규화

SKILL.md와 db-orchestrator.md 간 도메인명 통일:

| 코드 | 통일 명칭 |
|------|----------|
| A | Storage Engine |
| B | Index & Query Plan |
| C | Concurrency & Locking |
| D | Schema & Normalization |
| E | I/O & Buffer Management |
| F | Distributed & Replication |

#### 4-3. Hook 확장

plugin.json에 추가:
- `PostToolUse` (Write/Edit): constraints.json 스키마 검증
- `Stop`: `archive_constraints()` + `cleanup_session_history()` 호출

#### 4-4. NEVER 섹션 보완

`a1-engine-selector`와 `d3-access-pattern-modeler`에 NEVER 섹션 추가.

---

## 실행 우선순위 매트릭스

| 순위 | 이슈 | 심각도 | 공수 | 영향 범위 |
|------|------|--------|------|----------|
| 1 | C-1: SKILL.md 에이전트 경로 수정 | CRITICAL | 낮음 | 전체 DB 라우팅 |
| 2 | C-2: 오케스트레이터↔신시사이저 스키마 | CRITICAL | 중간 | 크로스시스템 전체 |
| 3 | C-3: 세션 히스토리 정리 메커니즘 | CRITICAL | 중간 | 장기 운영 안정성 |
| 4 | C-4: Phase 간 컨텍스트 정리 | CRITICAL | 높음 | 토큰 예산 정합성 |
| 5 | H-1: LLM 분류 폴백 | HIGH | 중간 | 모호 쿼리 라우팅 |
| 6 | H-3: 레퍼런스 타겟 로딩 | HIGH | 중간 | 토큰 효율 67% 개선 |
| 7 | H-5: 에러 코드 통합 | HIGH | 낮음 | 디버깅/운영 |
| 8 | H-6: 테스트 시나리오 | HIGH | 중간 | 검증 가능성 |
| 9 | M-1: 우선순위 매트릭스 통합 | MEDIUM | 낮음 | 충돌 해결 일관성 |
| 10 | M-3: 도메인 명칭 통일 | MEDIUM | 낮음 | 문서 정합성 |

---

## 업데이트된 스코어카드

| 차원 | 이전 (v1) | 11개 수정 후 (v2) | 현재 감사 기준 | 목표 (v3) |
|------|----------|-----------------|-------------|----------|
| 라우팅 정확성 | 60% | 100% | 100% | 100% |
| 에이전트 템플릿 일관성 | 95% | 95% | **99%** | 100% |
| Input/Output 커플링 | 85% | 90% | **100%** | 100% |
| DB 레퍼런스 품질 | C+ | A | **A** | A |
| 토큰 예산 정확성 | 70% | 95% | **60%** (실측 기준) | 90% |
| 세션 지속성 | 0% | 100% | **70%** (정리 미구현) | 95% |
| 스키마 정합성 | — | — | **40%** (SKILL.md↔실제) | 95% |
| 에러 핸들링 | 90% | 90% | **65%** (코드체계/재시도) | 90% |
| 컨텍스트 관리 | — | — | **50%** (정리 미구현) | 85% |
| 테스트 가능성 | — | — | **20%** (시나리오 없음) | 70% |
| **종합** | **7.5/10** | **9.2/10** | **7.0/10** (신규 기준) | **9.0/10** |

> v2에서 점수가 하락한 것은 감사 기준이 확대되었기 때문 (스키마 정합성, 컨텍스트 관리, 테스트 가능성이 새 평가 축으로 추가됨).

---

## 부록 A: 토큰 크기 상세

### 전체 코드베이스: 22,304줄 (44,608 est. 토큰)

| 컴포넌트 | 줄 수 | 추정 토큰 | 비고 |
|----------|------|----------|------|
| SKILL.md | 624 | 1,248 | 항상 로딩 |
| Resources (전체) | 2,342 | 4,684 | Phase별 로딩 |
| 오케스트레이터 (4) | ~1,000 | 2,000 | 시스템별 |
| 마이크로 에이전트 (40) | 5,806 | 11,612 | 도메인별 |
| 신시사이저 | 292 | 584 | 크로스시스템 |
| DB 레퍼런스 (17) | 5,299 | 10,598 | 에이전트별 |
| BE 레퍼런스 (11) | 5,857 | 11,714 | 클러스터별 |
| 스크립트 | 284 | 568 | 유틸리티 |

### 세션 메타데이터 (무한 성장)

| 항목 | 쿼리당 | 100쿼리 | 365일 |
|------|--------|---------|------|
| session-history.jsonl | ~350 토큰 | 35K | 120K+ |
| pattern-cache.json | — | ~5K | ~9K |
| constraints-archive | ~3K/세션 | 300K | 1M+ |

---

## 부록 B: 실행 패턴별 컨텍스트 소비

| 패턴 | Core | Resources | Agents | Refs | Outputs | 합계 | 예산 | 초과 |
|------|------|-----------|--------|------|---------|------|------|------|
| Shallow | 1.2K | 0.6K | 0.3K | 0.4K | 0.2K | 2.7K | 2.5K | +8% |
| Analysis | 1.2K | 1.2K | 0.6K | 0.8K | 0.5K | 4.3K | 5.0K | -14% |
| Impl Guide | 1.2K | 1.2K | 1.2K | 1.6K | 1.0K | 6.2K | 7.0K | -11% |
| Test Gen | 1.2K | 1.2K | 1.5K | 2.0K | 1.5K | 7.4K | 8.0K | -8% |
| Full Pipeline | 1.2K | 1.5K | 2.0K | 2.5K | 2.0K | 9.2K | 10.0K | -8% |
| Cross-System | 1.2K | 2.5K | 3.0K | 3.5K | 3.0K | 13.2K | 11.0K | **+20%** |

---

## 부록 C: 에이전트 모델 할당 전체 목록

### DB 에이전트 (14 Sonnet + 3 Haiku)

| 에이전트 | 모델 | 근거 |
|---------|------|------|
| a1-engine-selector | sonnet | 다차원 정량적 추론 |
| a2-compaction-strategist | **haiku** | 결정 매트릭스 + 공식 계산 |
| b1-index-architect | sonnet | 다중 쿼리 최적화 추론 |
| b2-join-optimizer | sonnet | 조합적 조인 순서 분석 |
| b3-query-plan-analyst | sonnet | 엔진별 EXPLAIN 파싱 |
| c1-isolation-advisor | sonnet | 격리 수준 간 이상 현상 상호작용 |
| c2-mvcc-specialist | sonnet | 엔진 내부 자료구조 이해 |
| c3-lock-designer | **haiku** | 확립된 패턴 선택 |
| d1-schema-expert | sonnet | 함수 종속성 분석 |
| d2-document-modeler | sonnet | 다중 요소 의사결정 분석 |
| d3-access-pattern-modeler | sonnet | 접근 패턴 간 충돌 분석 |
| e1-page-optimizer | sonnet | 데이터 분포 + 스토리지 추론 |
| e2-wal-engineer | sonnet | 내구성 보장 + 복구 시간 계산 |
| e3-buffer-tuner | **haiku** | 공식 기반 사이징 |
| f1-replication-designer | sonnet | 장애 도메인 + 일관성 트레이드오프 |
| f2-consistency-selector | sonnet | 분산 시스템 이론 (CAP/PACELC) |
| f3-sharding-architect | sonnet | 데이터 분포 + 파티션 키 트레이드오프 |

### BE 에이전트 (18 Sonnet)

| 클러스터 | 에이전트 | 모델 |
|---------|---------|------|
| S (Structure) | s1~s5 | 전체 sonnet |
| B (Boundary) | b1~b5 | 전체 sonnet |
| R (Resilience) | r1~r4 | 전체 sonnet |
| T (Test) | t1~t4 | 전체 sonnet |
