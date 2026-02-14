# Verification Tiers

> A protocol that automatically adjusts the verification level based on the scale of changes

## Tier Determination Criteria

| Tier | Condition | Verification Scope |
|------|-----------|-------------------|
| **LIGHT** | Changed files ≤ 4 AND changed lines ≤ 99 AND single layer | Only the relevant layer's checklist |
| **STANDARD** | 5 ≤ files ≤ 19 OR multi-layer (default) | Full 6-category + Cross-Layer checklist |
| **THOROUGH** | Changed files ≥ 20 OR security-related OR architecture change | Full checklist + build verification + sub-agent review |

### Minimum Tier Guarantee

- When loop is specified, **minimum STANDARD** is applied (not reduced below LIGHT)

## Tier Auto-determination Logic

```
1. Count changed files: git diff --name-only | wc -l
2. Count changed lines: git diff --stat | tail -1
3. Count affected layers: Extract layers from changed file paths
4. Check security keywords: auth, security, password, token, encrypt, permission
5. Determine Tier:
   - Files ≥ 20 OR security keywords detected OR architecture change → THOROUGH
   - Files ≤ 4 AND lines ≤ 99 AND 1 layer → LIGHT
   - Otherwise → STANDARD
```

---

## LIGHT Tier

### Applicable Targets
- Single file bug fix
- Adding a parameter to an existing method
- Adding Definition fields
- Simple naming fixes

### Verification Items
```
□ Relevant layer checklist for changed files
□ Naming conventions
□ Import inspection for changed files (star imports)
□ LLM direct review: #1 UseCase cross-ref, #2 Domain immutability, #3 Entity conversion (changed files only)
```

### Script Execution
```bash
verify-conventions.sh {changed file path} summary
```

---

## STANDARD Tier

### Applicable Targets
- New feature implementation (Use Case + Repository + Controller)
- Refactoring (Port extraction, Definition pattern application)
- Adding tests

### Verification Items
Full 6-category checklist:
1. Architecture layers
2. Code style
3. Naming
4. JPA patterns
5. Testing
6. Git conventions
7. LLM direct review: #1 UseCase cross-ref, #2 Domain immutability, #3 Entity conversion, #4 Architecture direction
8. Cross-Layer Coverage (LLM): Port Coverage, UseCase Coverage, Model-Entity Parity, DTO Completeness

### Script Execution
```bash
verify-conventions.sh {project root} detailed
```

**Static analysis (allow-list based):**
```
□ scripts/run-static-analysis.sh {project root} STANDARD
  → spotless, detekt, checkstyle (STANDARD level tools only)
  → Skip if allow-list is not configured
```

---

## Tier × Model Routing (v2.4)

검증 티어에 따라 권장 모델을 자동으로 선택하여 비용과 성능을 최적화한다.

### 티어별 권장 모델

| Verification Tier | 권장 Model | 근거 | 예상 비용 절감 |
|-------------------|-----------|------|---------------|
| **LIGHT** | `haiku` | 5파일 이하, 단순 스타일 검증 — 속도 우선 | 기준 대비 -80% |
| **STANDARD** | `sonnet` | 기본 6-카테고리 + Cross-Layer 검증 — 균형 | 기준 (baseline) |
| **THOROUGH** | `opus` | 아키텍처 결정, 보안, 20+ 파일 — 정밀도 우선 | 기준 대비 +200% |

### 자동 에스컬레이션 규칙

LIGHT 티어로 시작한 후 위반 발견 시 자동으로 상위 티어로 승격:

```
시작: LIGHT (haiku)
  │
  ├── 아키텍처 위반 발견 (레이어 경계, 의존성 방향)
  │   └── → STANDARD로 승격 (sonnet)
  │
  ├── 보안 키워드 감지 (auth, encrypt, permission, token)
  │   └── → THOROUGH로 승격 (opus)
  │
  ├── 동일 위반 2회 연속
  │   └── → 한 단계 승격 (LIGHT→STANDARD 또는 STANDARD→THOROUGH)
  │
  └── Domain 키워드 사용 (`security` 키워드)
      └── → THOROUGH 강제 적용
```

### 모델 전환 시점

| 전환 조건 | 현재 → 다음 | 재시작 필요 |
|----------|------------|------------|
| 아키텍처 위반 | LIGHT → STANDARD | 현재 Loop에서 즉시 적용 |
| 보안 키워드 | ANY → THOROUGH | 현재 Loop에서 즉시 적용 |
| 동일 위반 2회 | 현재 → 상위 | 다음 Loop에서 적용 |
| 에스컬레이션 후 위반 0 | 유지 | 디에스컬레이션 없음 |

**주의:** 에스컬레이션 후에는 디에스컬레이션하지 않음. 한 번 THOROUGH로 승격되면 해당 세션에서 유지.

### 전환 실행 메커니즘

| 전환 유형 | 시점 | 기존 검증 결과 처리 |
|----------|------|-------------------|
| **[A] 즉시 전환** (아키텍처/보안 위반) | 현재 Loop 내 위반 감지 즉시 | 기존 결과 폐기, 상위 모델로 전체 재검증 |
| **[B] 경계 전환** (동일 위반 2회) | 현재 Loop 완료 후, 다음 Loop 시작 시 | 현재 Loop 결과 유지, 다음 Loop부터 상위 모델 |

**[A] 즉시 전환 시 전체 재검증 근거:**
하위 모델의 "통과"가 상위 모델에서도 통과를 보장하지 않는다.
일관성을 위해 전환 후 전체 파일 재검증 필수.

**전환 알림:**
```
⚠️ [Escalation] {trigger_reason}
   {CURRENT_TIER} ({current_model}) → {NEXT_TIER} ({next_model})
   Re-verifying {N} files...
```

---

## THOROUGH Tier

### Applicable Targets
- 20 or more files changed
- Security-related changes (authentication, authorization, encryption)
- Architecture changes (adding new layers, module separation)
- Data migration

### Verification Items
All of STANDARD + additional:

**Kotlin (language=kotlin):**
```
□ ./gradlew compileKotlin succeeds
□ ./gradlew test succeeds
□ ./gradlew ktlintCheck succeeds
□ scripts/run-static-analysis.sh {project root} THOROUGH succeeds (allow-list based)
□ Cross-reference verification for all changed files
□ Sub-agent code review (architecture perspective)
```

**Java (language=java):**
```
□ ./gradlew compileJava succeeds
□ ./gradlew test succeeds
□ ./gradlew checkstyleMain succeeds (when checkstyle plugin detected)
□ ./gradlew spotlessCheck succeeds (when spotless plugin detected)
□ scripts/run-static-analysis.sh {project root} THOROUGH succeeds (allow-list based)
□ Cross-reference verification for all changed files
□ Sub-agent code review (architecture perspective)
```

**Mixed (language=mixed):**
```
□ ./gradlew compileKotlin compileJava succeeds
□ ./gradlew test succeeds
□ ./gradlew ktlintCheck succeeds
□ ./gradlew checkstyleMain succeeds (if present)
□ scripts/run-static-analysis.sh {project root} THOROUGH succeeds (allow-list based)
□ Cross-reference verification for all changed files
□ Sub-agent code review (architecture perspective)
```

### Sub-agent Review Protocol

In the THOROUGH Tier, a separate review sub-agent is spawned:

```
Review agent input:
- List of changed files (git diff --name-only)
- references/shared/layering-principles.md (always)
- references/shared/hexagonal-architecture.md (always)
- references/kotlin/code-style-guide.md (or java/code-style-guide.md)

Review perspectives:
1. Whether dependency direction between layers is violated
2. Whether domain model is polluted (infrastructure concepts leaking in)
3. Appropriateness of transaction boundaries
4. Consistency of error handling
```

---
