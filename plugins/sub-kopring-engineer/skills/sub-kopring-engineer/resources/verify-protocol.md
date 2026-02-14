# Verify Protocol

> Phase 4 (Verify) detailed execution procedure

> When a profile exists, verification target paths and rules are dynamically adjusted based on the profile.
> `scripts/verify-conventions.sh` automatically reads and uses the profile's layer paths.
> If the profile's architecture is not hexagonal, hexagonal-specific verification rules are skipped.

## Required Reads (skip if already loaded in this session)
> Base Set: see SKILL.md "Context Documents" section (profile, learned patterns, code-style-guide, architecture ref)

**Phase-specific additions:**
- `resources/verification-tiers.md` (for tier determination)
- `references/shared/layering-principles.md` (when STANDARD/THOROUGH)
- `references/kotlin/unit-testing.md` (when language=kotlin/mixed)
- `references/java/unit-testing.md` (when language=java/mixed)
- `references/shared/git-conventions.md` (always)
- `resources/error-playbook.md` (when violations are found)

---

### 3-0. Verify Preparation

```
1. Check previous Verify snapshot: ~/.claude/cache/sub-kopring-engineer-{hash}-verify-snapshot.json
   - If exists: Reference previous violation count and timestamp to assess improvement
   - If not: Treat as first verification
2. From Loop 2 onward, switch to incremental verification:
   - scripts/verify-conventions.sh [target path] [output format] --changed-only
   - Only verify files modified in the previous loop
3. Loop 1 or standalone verify: Full verification (default mode)
4. **Context Health Check** (Loop 2+ 시작 시):
   - 컨텍스트 사용량 70% 이상 → WARNING 출력
   - 80% 이상 → `/compact` 권장 메시지 출력
   - 85% 이상 → 즉시 `/compact` 실행 필수, 실행 후 verify-snapshot.json 기반 복구
   - (see SKILL.md Context Health Protocol)
```

### 3-0a. Verified-Clean Registry (Loop 2+, v2.7)

verify-snapshot.json에 검증 통과 파일 레지스트리를 관리하여 부분 성공을 보존하고 회귀를 감지한다.

**확장 스키마** (기존 배열과 호환):
```json
{
  "meta": {
    "profile_hash": "abc123...",
    "created_at": "2026-02-11T10:00:00"
  },
  "history": [
    {"timestamp": "...", "total": 10, "passed": 8, "violations": 2, "warnings": 1}
  ],
  "verified_clean": {
    "OrderService.kt": { "passed_categories": "all", "loop_verified": 2 }
  },
  "violations_active": {
    "OrderController.kt": { "category": "Naming", "since_loop": 1, "consecutive_count": 2 }
  },
  "regression_guard": ["OrderService.kt"]
}
```

**Profile Hash 불일치 시 동작 (M4):**

| 상황 | 동작 |
|------|------|
| `meta.profile_hash` == current | 정상 진행 |
| `meta.profile_hash` != current | WARN 출력 + `verified_clean` 레지스트리 초기화 (Profile 변경 = 이전 검증 무효) |
| `meta.profile_hash` 없음 (v3.0 이전) | 무시 (하위 호환) |

**규칙**:
| 이벤트 | 동작 |
|--------|------|
| 파일이 모든 카테고리 통과 | `verified_clean`에 등록 |
| fix가 `verified_clean` 파일을 수정 | `regression_guard`로 이동 |
| `regression_guard` 파일이 재검증 통과 | `verified_clean`으로 복귀 |
| `regression_guard` 파일에서 새 위반 | **REGRESSION** 플래그 — 고우선순위로 Verify 테이블에 표시 |
| 루프 종료 | `regression_guard` 비움 (다음 세션에서 클린 시작) |

**`--changed-only` 모드 통합**:
- LLM이 `--changed-only` 실행 시 `regression_guard` 파일도 검증 대상에 포함 지시
- `verified_clean` 파일은 수정되지 않은 한 검증 스킵

**관리 주체**: LLM이 Verify 결과 기반으로 갱신 (스크립트의 `save_verify_snapshot`은 기존 집계 데이터 계속 추가)

### 3-0b. Learned Patterns Cross-validation (STANDARD/THOROUGH only)

1. Load learned patterns cache
2. Naming pattern cross-validation: Verify class names in changed/created files are consistent with existing naming patterns
3. Annotation combo cross-validation: Verify annotation combinations in changed files match existing combo patterns
4. Custom annotations cross-validation: Check for duplicate creation of new annotations with the same purpose as existing custom annotations
5. Results are WARN level — no impact on loop termination conditions

### 3-1. Verification Checklist (6 categories)

Detailed rules for each category are verified against the loaded references/ documents.
Items automatically checked by `scripts/verify-conventions.sh` do not require manual verification.
Items marked **(LLM)** are NOT checked by the script — verify by reading the changed files directly.

1. **Architecture layers** — Dependency direction, layer constraints, circular references (→ architecture reference)
2. **Code style** — No single-use extraction, DI patterns, imports (→ code-style reference)
3. **Naming** — Class/method patterns (*JpaEntity, *Service, *RestController, etc.) (→ code-style reference)
4. **JPA patterns** — @DynamicUpdate, Entity-Model separation (→ architecture reference)
5. **Testing** — SUT pattern, Fake/Mock, assertion libraries, structure (→ testing reference)
6. **Git conventions** — Commit messages, branch names (→ `references/git-conventions.md`)

### 3-1a. LLM Direct Review Items

Items that require contextual understanding and cannot be reliably detected by static pattern matching.
Verify by reading the changed files directly after reviewing `verify-conventions.sh` results.

1. **UseCase cross-reference**: Check whether Services in the application layer inject other Services directly. Indirect references through Ports are allowed.
   → Read constructor/field injections of changed Service files and judge by intent

2. **Domain model immutability**: Check whether application layer code directly mutates domain model state (copy(), setter, direct field assignment, etc.).
   → Read changed application layer files and judge

3. **Entity-Model conversion**: Check whether newly created/modified JPA Entities have a conversion function to the domain model. Function name follows project convention (toModel, toDomain, etc.).
   → Read changed Entity files and judge

4. **Architecture direction** (STANDARD+): Check whether dependency directions between changed files comply with hexagonal architecture rules.
   → Read imports of changed files and judge

### 3-1b. Static Analysis Tool Execution (STANDARD/THOROUGH)

**Execution condition**: Tier is STANDARD or above AND `.sub-kopring-engineer/static-analysis-tools.txt` is configured

```
1. Execute scripts/run-static-analysis.sh {project root} {STANDARD|THOROUGH}
2. Include results in the Verify table under "Static Analysis" category
3. If allow-list is not-configured or none → skip entirely
```

**Auto-fix protocol on Spotless failure**:
- `spotlessCheck` fails → AI decides whether to execute `./gradlew spotlessApply`
- Re-verify after running `spotlessApply` (run-static-analysis.sh only performs checks)
- If still failing after auto-fix, report as needing manual fix

**Result format**:
```markdown
| # | Category | Violation | File:Line | Description | Fix |
|---|----------|-----------|-----------|-------------|-----|
| N | Static Analysis | spotless violation | — | Format mismatch | Run spotlessApply |
| N | Static Analysis | detekt violation | Service:15 | LongMethod | Split method |
```

### 3-1c. Test Coverage Check with Sister Skill (Optional)

**Execution condition**:
- `sister-skills.sub-test-engineer.enabled: true` in profile.yaml
- Coverage tool configured in test-profile.json
- Coverage below threshold (default: 80%)

**Procedure**:
```
1. Run coverage measurement:
   → scripts/measure-coverage.sh [project-root] [target-package]
   → Parse coverage percentage

2. IF coverage >= threshold:
   → Log: "Coverage {N}% meets threshold {M}%"
   → Skip sister skill invocation

3. IF coverage < threshold AND sister-skill enabled:
   → Identify uncovered files/lines from coverage report
   → Compose <sister-skill-invoke> message:

     <sister-skill-invoke skill="sub-test-engineer">
       <context>
         <caller>sub-kopring-engineer</caller>
         <phase>verify</phase>
         <trigger>coverage-gap</trigger>
       </context>
       <targets>
         <file path="{uncovered-file}">
           <uncovered-lines>{line-ranges}</uncovered-lines>
           <uncovered-methods>{method-names}</uncovered-methods>
         </file>
       </targets>
       <constraints>
         <technique>unit-test</technique>
         <coverage-target>{threshold}%</coverage-target>
         <max-loop>2</max-loop>
       </constraints>
     </sister-skill-invoke>

4. Invoke sub-test-engineer (if available):
   → IF auto-invoke: true → invoke directly
   → IF auto-invoke: false → prompt user: "Coverage {N}% below {M}%. Invoke sub-test-engineer? [y/N]"

5. Await <sister-skill-result>:
   → IF status=completed: Re-run coverage measurement, log delta
   → IF status=partial: Log issues, continue with partial improvement
   → IF status=failed: Log warning, add to Verify report

6. IF sub-test-engineer unavailable:
   → Log: "Sister skill sub-test-engineer not available"
   → Add to Verify report: "Coverage {N}% below threshold, manual test generation recommended"
```

**Result integration**:
```markdown
## Verify Results [Loop 1/3] — STANDARD

### Test Coverage
- Before: 65% line coverage
- Sister skill invocation: sub-test-engineer (coverage-gap)
- After: 82% line coverage (+17%)
- Status: ✅ Threshold met

### Generated Tests
| File | Tests Added | Coverage Delta |
|------|-------------|----------------|
| OrderCancelServiceTest.kt | 7 | +17% |
```

> Protocol details: [docs/invoke-protocol.md](../../../../docs/invoke-protocol.md)

### 3-1d. Cross-Layer Coverage Check (LLM — STANDARD/THOROUGH only)

레이어 간 배선 완결성을 검증한다. 기존 6카테고리가 레이어 내부 일관성을 검증한다면,
이 검증은 레이어 간 연결 누락을 탐지한다.

**실행 조건**:
- STANDARD 이상에서만 실행 (LIGHT 스킵)
- `--changed-only` 모드: 변경된 파일의 관련 교차 검증만 수행

**검증 항목**:

1. **Port Coverage**: :core의 Port 인터페이스(Reader/Appender/Updater/Port) 목록 → :infrastructure에 Adapter 구현 존재 확인
   → Glob으로 Port 파일 목록 추출, Read로 인터페이스 확인, Grep으로 Adapter에서 구현 탐색
   → 미구현 Port: ERROR (기능 미완성)

2. **UseCase Coverage**: :application의 UseCase/Service public 메서드 → :api에 Controller 엔드포인트 연결 확인
   → Read로 Service 메서드 시그니처 확인, Grep으로 Controller에서 호출 탐색
   → 미연결 UseCase: WARN (내부 전용일 수 있음)

3. **Model-Entity Parity**: 변경된 Domain Model → 대응 JPA Entity 존재 확인
   → 변경된 Model 파일 기준 :infrastructure에서 Entity 파일 탐색
   → 미대응: ERROR (데이터 저장 불가)

4. **DTO Completeness**: 변경된 Domain Model 필수 필드 → Controller DTO에 필드 존재 확인
   → Domain Model 필드 읽기, DTO 필드와 비교
   → 누락 필드: WARN (의도적 제외일 수 있음)

**결과를 기존 Verify Results 테이블에 Cross-Layer 카테고리로 추가:**
```markdown
| # | Category | Violation | File:Line | Description | Fix |
|---|----------|-----------|-----------|-------------|-----|
| N | Cross-Layer | Orphan Port | OrderReader.kt | Adapter 미구현 | :infrastructure에 OrderReaderAdapter 생성 |
```

### 3-2. Verification Result Output

**Format rules:**
- `Passed: X/Y` means "X checks passed out of Y total checks"
- `Fix` column must use imperative verb form: "Move X to Y", "Add Z", "Remove W"

```markdown
## Verify Results [Loop 1/3] — STANDARD

### Passed: 4/6 items
### Violations: 2 items

| # | Category | Violation | File:Line | Description | Fix |
|---|----------|-----------|-----------|-------------|-----|
| 1 | Architecture | Use Case reference | OrderService:15 | Direct repository call in Use Case | Move repository call to Adapter via Port |
| 2 | Naming | Suffix mismatch | OrderCancel:1 | Missing *Service suffix | Rename OrderCancel to OrderCancelService |

### Auto-fix
Fixing the above violations...

### Fix Complete Summary
- Fixed: 2 items
- Remaining violations: 0 items → ✅ Early loop termination
```

#### Fix Guide (STANDARD+ 보충 섹션, v2.7)

STANDARD/THOROUGH Tier에서 위반이 존재할 때, 기본 테이블 아래에 보충 정보를 추가한다.

```markdown
### Fix Guide

| # | Fix Direction | Reference Example | Related Files |
|---|---------------|-------------------|---------------|
| 1 | Port 인터페이스 추출 → Adapter 경유 주입 (hexagonal-architecture.md §Layer constraints) | UserService.kt:23 — Port 경유 패턴 참조 | OrderPort.kt, OrderAdapter.kt |
```

**생성 규칙**:
- `Fix Direction`: 해당 카테고리의 references/ 문서 규칙에서 도출 + 적용 근거 명시
- `Reference Example`: learned patterns 또는 Grep으로 동일 패턴의 기존 성공 사례 탐색
  - 사례 없으면 아래 Fallback 절차 적용
- `Related Files`: 위반 파일의 import/의존성 + fix에 생성/수정해야 할 파일 목록

**Reference Example Fallback (사례 미발견 시):**

| 단계 | 탐색 범위 | 결과 시 |
|------|----------|--------|
| 1차 | 동일 카테고리 + 동일 레이어의 기존 코드 Grep | 발견 → 해당 파일:라인 기재 |
| 2차 | 동일 카테고리 + 인접 레이어의 유사 패턴 Grep | 발견 → "(유사 패턴)" 주석과 함께 기재 |
| 3차 | 미발견 | `"No existing pattern. See {reference-doc} §{section}"` 기재 |

3차 Fallback 시 Tier별 추가 조치:
- **STANDARD**: Fix Direction만 제시. 참조 문서 섹션 명시.
- **THOROUGH**: Fix Direction + 참조 문서 섹션 + "패턴 부재 — 향후 패턴 학습 대상" 메모 추가.

**Tier별 생성 범위**:
- **LIGHT**: 기본 테이블만 출력 (Fix Guide 생략)
- **STANDARD**: Fix Direction + Reference Example 포함
- **THOROUGH**: 전체 3필드 포함

### 3-3. Loop Convergence Failure Handling

**Violation history tracking:**
The verify-snapshot.json의 `history` 배열에 각 루프 결과가 누적된다 (스키마: §3-0a 참조). At the start of each loop (2+):
1. Read the snapshot file to get the `history` array and `verified_clean`/`regression_guard` state
2. Compare the current loop's violation categories/descriptions with previous loops
3. Track consecutive identical violations by matching category + file pattern

**동일 위반 판정 기준 (Violation Identity Matching):**

두 위반 V₁ (Loop N), V₂ (Loop N+1)이 "동일"하려면 다음 3조건을 모두 충족해야 한다:

| # | 조건 | 매칭 규칙 | 근거 |
|---|------|----------|------|
| 1 | Category | V₁.category == V₂.category (완전 일치) | 6+1 카테고리 중 하나 |
| 2 | File | basename(V₁.file) == basename(V₂.file) | 라인 번호 무시 — fix 시도 후 라인 이동 가능 |
| 3 | Consecutive | V₂.loop == V₁.loop + 1 (연속 루프) | 중간에 해소된 위반은 카운트 리셋 |

**매칭 대상이 아닌 필드:**
- `line`: 무시 (fix 시도 시 라인 이동 발생)
- `message`: 참고용 (비교 대상 아님 — 표현이 달라도 근본 원인 동일 가능)
- `description`: 참고용

**카운트 분기:**
- 2회 연속 동일 위반 → Tier 에스컬레이션 (verification-tiers.md 참조)
- 3회 연속 동일 위반 → Root Cause Analysis Sub-agent 스폰 (error-playbook.md §5 참조)

| Consecutive identical violation count | Response |
|--------------------------------------|----------|
| 1st | Normal fix attempt |
| 2nd | Change approach (re-implement with different pattern) |
| 3rd | Spawn root cause analysis sub-agent |

**Root cause analysis agent protocol:**
→ [error-playbook.md §5 "Root cause analysis enhanced procedure (v2.7)"](./error-playbook.md#5-repeated-architecture-violations) 참조.
TACTICAL/STRUCTURAL 분류 기반으로 Fix 이력 수집 → 원인 분류 → 재설계 프로토콜을 수행한다.

### 3-4. Post-task Pattern Capture (user confirmation-based)

After all Verify loops are complete, patterns used in this task are confirmed with the user and fed back to the cache.

**Procedure:**
1. Detect: Execute `scripts/capture-task-patterns.sh --detect [project root] --files "{changed files}"`
2. Present: Display detected pattern candidates to the user and ask about learning each pattern
   - "The following patterns have been detected. Please select the items to learn:"
   - If the user rejects all, terminate without cache changes
3. Save: Save only approved items via `scripts/capture-task-patterns.sh --save [project root] --patterns "..."`

**User prompt example:**
```
The following patterns were detected in this task:
1. [naming] *Handler — OrderCancelHandler, PaymentHandler
2. [base] BaseUseCase → OrderCancelService
3. [dependency] OrderCancelService ← OrderReader, OrderUpdater, PaymentPort
4. [structure] application: single UseCase per file, execute(Command)->Result
5. [fixture] OrderFixture — used in OrderCancelServiceTest

Please select the patterns to apply in future code generation.
Unselected items will not be saved.
```

**Design principles:**
- No automatic saving — Prevents learning biased/incorrect patterns
- User rejection = ignore that pattern (can be detected again in future tasks)
- Task-Derived Patterns section is preserved even when learn-patterns.sh is re-executed
- If 0 pattern candidates exist, terminate silently without prompting

### 3-5. AST-grep Rule Generation (v3.0, Extended)

> 상세: [resources/extended/ast-grep-rules.md](./extended/ast-grep-rules.md)

ast-grep 설치 + 5개 이상 패턴 캐시 시, 학습된 패턴에서 AST-grep 규칙 자동 생성을 제안한다.
스크립트: `scripts/generate-ast-rules.sh [--preview|--apply]`

---

## Phase Handoff

**Entry Condition**: Phase 3 Implement complete (files written) AND Verify Transition Contract 통과 (see implement-protocol.md §Phase Handoff):
```
□ 최소 1개 파일 변경됨 (변경 0개 시 Verify 스킵)
□ 테스트 코드 작성됨 (누락 시 Implement 계속)
□ snapshot.json 갱신됨
```

**Exit → Loop/종료 Transition Contract (v2.6):**
Verify Loop 종료 전 아래를 확인한다:
```
□ 검증 결과 테이블 (6-카테고리 + Cross-Layer violations + fixes) 생성 완료
  → 테이블 없이 Loop 종료 불가. 위반 0개여도 "Passed: N/N items" 테이블 출력
□ Session Wisdom: 아키텍처 결정 또는 이슈 해결이 있었으면 PROGRESS.md 기록
```

**Exit Condition**: Loop convergence (0 violations) OR max loops reached

**Next Phase**: Session end OR new task cycle

**Domain Keyword Effects**:
- `jpa-focus`: JPA 검증 강화 — Entity-Model 분리, 연관관계 매핑 검증
- `security`: 보안 관련 검증 THOROUGH 강제
- `test-heavy`: 테스트 커버리지 검증 강화

**Session Wisdom**: Loop 완료 시 `.sub-kopring-engineer/PROGRESS.md`에 아키텍처 결정/이슈 해결 기록 (see SKILL.md Session Wisdom Protocol)
