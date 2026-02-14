# Error Playbook

> Resolution protocols for frequently occurring error types

## Quick Index (에러 시그니처 → 섹션)

| 에러 시그니처 | 섹션 | 키워드 |
|-------------|------|--------|
| `BeanCurrentlyInCreationException` | [1. Circular Dependency](#1-circular-dependency) | 순환 의존성 |
| `Type mismatch`, `Required: X, Found: Y` | [2. Compilation Error](#2-compilation-error--type-mismatch) | 타입 불일치 |
| `MockK`, `every { }`, `verify { }` | [3. Test Failure — MockK](#3-test-failure--mockk-related) | MockK 관련 |
| `FixtureMonkey`, `ArbitraryBuilder` | [4. Test Failure — FixtureMonkey](#4-test-failure--fixturemonkey-related) | FixtureMonkey |
| 동일 위반 3회 반복 | [5. Repeated Violations](#5-repeated-architecture-violations) | 수렴 실패, TACTICAL, STRUCTURAL |
| `pre-commit hook`, `git commit` 실패 | [6. Git Commit Failure](#6-git-commit-failure) | Git Hook |
| `LazyInitializationException`, `@ManyToOne` | [7. JPA Entity](#7-jpa-entity-related) | JPA 연관관계 |
| `detekt`, `MaxLineLength`, `ComplexMethod` | [8. detekt Violations](#8-detekt-violations) | 정적 분석 |
| `spotless`, `ktfmt`, `ktlint` | [9. Spotless Violations](#9-spotless-violations) | 포맷팅 |
| 모듈 간 의존성 위반 | [10. Multi-Module Dependency](#10-multi-module-dependency-violations) | 모듈 경계 |
| `ArchUnit`, `LayeredArchitecture` | [11. ArchUnit Violations](#11-archunit-violations) | 아키텍처 검증 |
| `@Deprecated`, `error prone` | [12. Error Prone](#12-error-prone-violations) | 에러 프론 |

---

## When to Use

Reference this document when the same error repeats during the Verify loop, or when build/test failures occur during Implement.

> **Verification scope**: Not all errors are checked at every tier. See [verification-tiers.md](./verification-tiers.md) for which tools run at LIGHT/STANDARD/THOROUGH levels.
> **Static analysis**: Tools like detekt/spotless/checkstyle only run if configured in `.sub-kopring-engineer/static-analysis-tools.txt`. See [project-discovery-protocol.md Step 5](./project-discovery-protocol.md).

---

## Error Type-specific Responses

### 1. Circular Dependency

**Symptoms**: Spring Bean creation failure, `BeanCurrentlyInCreationException`

**Root cause analysis order**:
1. `Grep: "class.*Service.*private val.*Service"` — Check inter-Use Case references
2. `Grep: "@Component\|@Service\|@Repository"` — Check bean registration

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Inter-Use Case reference | Abstract through Port interface (references/hexagonal-architecture.md) |
| Inter-Repository reference | Change to direct JPA Repository usage |
| Event listener reference | Switch to `@Lazy` or domain event publishing pattern |

### 2. Compilation Error — Type Mismatch

**Symptoms**: `Type mismatch: inferred type is X but Y was expected`

**Resolution protocol**:
1. Check for missing Domain Model ↔ JPA Entity conversion → Add `toModel()` / `from()`
2. Check Definition pattern application → Use `Definition` instead of `copy()`
3. Check nullable handling → `getByIdOrNull` vs `getById` return types

### 3. Test Failure — MockK Related

**Symptoms**: `no answer found for`, `was not called`, `missing stubbing`

**Resolution protocol**:
| Error | Cause | Fix |
|-------|-------|-----|
| `no answer found` | Missing stubbing | Add `every { port.method(any()) } returns result` |
| `was not called` | Call order/condition | Check verify conditions, use `any()` matcher |
| Missing `clearMocks` | State pollution from previous test | Add `clearMocks()` in `@BeforeEach` |
| `spyk` vs `mockk` confusion | Need to spy on Fake object | Use `spyk(Fake...)` for internal deps, `mockk<>()` for external |

### 4. Test Failure — FixtureMonkey Related

**Symptoms**: Object creation failure, missing required fields

**Resolution protocol**:
```kotlin
// ❌ When default fixture creation fails
val entity = fixture<Entity>()

// ✅ Explicitly set required fields
val entity = fixture<Entity> {
    set(Entity::id, 0L)
    set(Entity::workspaceId, 1L)
    set(Entity::status, Entity.Status.ACTIVE)
}
```

### 5. Repeated Architecture Violations

**Symptoms**: Same architecture violation repeats 2+ times in the Verify loop

**3-Strike Escalation**:

| Strike | Response |
|--------|----------|
| 1st | Normal fix (code patch) |
| 2nd | Change approach — apply a different design pattern |
| 3rd | **Halt** — spawn root cause analysis sub-agent |

**Root cause analysis enhanced procedure (v2.7)**:

1. **Fix 이력 수집**: 3회 시도된 fix 이력을 구조화하여 수집
   | 시도 | 수정 내용 | 실패 원인 |
   |------|----------|----------|
   | 1st | {what was changed} | {why it failed} |
   | 2nd | {what was changed differently} | {why it still failed} |
   | 3rd | {what was attempted} | {why pattern repeats} |

2. **원인 분류**: TACTICAL vs STRUCTURAL 판별
   - **TACTICAL** (잘못된 fix): 올바른 이해 기반이나 수정 방향이 부정확
     → 동일 설계 내에서 변형된 접근 시도
     → 기존 코드베이스에서 동일 패턴의 성공 사례 탐색 (Grep/Glob)
   - **STRUCTURAL** (잘못된 이해): 근본적인 설계/이해가 부정확
     → 아래 재설계 프로토콜 진입

3. **STRUCTURAL 재설계 프로토콜**:
   a. 영향 받는 도메인 모델 + 의존성 체인 재읽기 (Read)
   b. 원래 Plan의 해당 컴포넌트 섹션 재읽기
   c. 이전 시도를 **회피**하는 새 설계안 제시
   d. 사용자 승인 후 구현

**TACTICAL vs STRUCTURAL 판별 기준**:
| 지표 | TACTICAL | STRUCTURAL |
|------|----------|-----------|
| 에러 위치 | 매번 같은 파일/라인 | 다른 파일에서 연쇄 실패 |
| 에러 유형 | 동일 유형 (e.g., Type mismatch) | 다른 유형으로 변화 |
| 수정 범위 | 1-2 파일 수정으로 해결 시도 | 3+ 파일에 걸친 변경 필요 |

### 3b. Test Failure — Mockito Related (Java)

**Symptoms**: `Unnecessary stubbings detected`, `Wanted but not invoked`, `NullPointerException on mock`

**Resolution protocol**:
| Error | Cause | Fix |
|-------|-------|-----|
| `Unnecessary stubbings` | Configured stubbing not called | `lenient().when(...)` or remove stubbing |
| `Wanted but not invoked` | Call order/condition | Check verify conditions, use `any()` matcher |
| NPE on mock return | Primitive return mock not configured | Set default values like `when(...).thenReturn(0L)` |
| `spy` vs `mock` confusion | Need to spy on Fake object | Use `spy(new Fake...)` for internal deps, `mock(...)` for external |
| `@InjectMocks` issue | Field injection failure | Change to manual constructor injection |

### 6. Git Commit Failure

**Symptoms**: pre-commit hook failure, ktlint/checkstyle violations

**Resolution protocol (Kotlin)**:
1. Run `./gradlew ktlintCheck` to check violation list
2. Auto-fix available: `./gradlew ktlintFormat`
3. Manual fix needed: star imports, line length exceeded, etc.

**Resolution protocol (Java)**:
1. Run `./gradlew checkstyleMain` to check violation list
2. With Spotless: `./gradlew spotlessApply` for auto-formatting
3. Manual fix: import cleanup, line length, braces, etc.

### 6b. Checkstyle/Spotless Errors (Java)

**Symptoms**: `checkstyleMain` failure, `spotlessCheck` violations

**Common violation types**:
| Violation | Fix |
|-----------|-----|
| `AvoidStarImport` | Replace with explicit imports |
| `LineLength` | Line break within 140 characters |
| `NeedBraces` | Add braces to if/else/for |
| `UnusedImports` | Remove unused imports |
| `MissingJavadocType` | Add Javadoc to public classes (when rule is active) |

### 7. JPA Entity Related

**Symptoms**: `@Entity`-related runtime errors, Flyway migration failures

**Checklist**:
```
□ @DynamicUpdate declared
□ equals/hashCode uses kotlinEquals/kotlinHashCode
□ toModel() conversion function exists
□ from() factory in companion object exists
□ @AttributeOverrides maps Embeddable column names
```

### 8. detekt Violations

**Symptoms**: `detekt` task failure, violation report output

**Common violation types**:
| Violation | Fix |
|-----------|-----|
| `LongMethod` | Split method into logical units (extract private helpers) |
| `MagicNumber` | Extract as constants (`companion object` or `const val`) |
| `ComplexCondition` | Convert to `when` expression or early return pattern |
| `LongParameterList` | Group into DTO/Command objects |
| `TooManyFunctions` | Separate related functions into separate classes/files |
| `MaxLineLength` | Line breaks, variable extraction to reduce line length |

**Resolution protocol**:
1. Run `./gradlew detekt` to check violation list
2. Fix by referencing the table above based on violation type
3. Check if project-specific exceptions exist in `detekt.yml`
4. Re-run after fix to confirm pass

### 9. Spotless Violations

**Symptoms**: `spotlessCheck` failure

**Resolution protocol**:
1. Run `./gradlew spotlessApply` → Auto-format fix
2. Review diff after auto-fix (check for unintended changes)
3. Re-run `spotlessCheck` to confirm pass
4. If auto-fix is insufficient, check spotless configuration file (`spotless` block in `build.gradle`)

**Note**: `spotlessApply` modifies files directly, so committing/stashing changes beforehand is recommended

### 10. Multi-Module Dependency Violations

**Symptoms**: `Module :order-infrastructure must not depend on :order-application`, build.gradle.kts 의존성 방향 위반

**Common violation patterns**:
| Pattern | Cause | Fix |
|---------|-------|-----|
| `core → application` | core에서 UseCase 직접 참조 | Port 인터페이스를 core에 정의하고 application이 구현 |
| `infrastructure → application` | Adapter에서 Service 직접 호출 | core의 Port만 구현, Service 로직은 application에 유지 |
| `{domain-A}-application → {domain-B}-application` | 도메인 간 직접 참조 | Domain Event 통신으로 전환 (hexagonal-architecture.md § Event-Driven) |
| shared-kernel 비대화 | 비즈니스 로직이 shared-kernel에 유입 | shared-kernel은 순수 타입만 허용, 로직은 각 도메인 core로 이동 |

**Resolution protocol**:
1. `verify-conventions.sh` 출력에서 위반 모듈 쌍 확인
2. 위반 build.gradle.kts에서 `project(":xxx")` 라인 제거
3. 필요한 경우 Port 인터페이스 추가 또는 Domain Event 도입
4. `bash -n` 후 빌드 확인

### 11. ArchUnit Violations

**Symptoms**: `*ArchTest*` test failure, architecture rule violations

**Common violation types**:
| Violation | Fix |
|-----------|-----|
| Package dependency violation | Move class to the correct package |
| Naming rule violation | Rename class to match rules (e.g., `*Controller`, `*Service`) |
| Layer access rule violation | Fix dependency direction, introduce interfaces |
| Circular reference detected | Resolve with event patterns or intermediate layer introduction |

**Resolution protocol**:
1. Check the rules in the failing ArchUnit test (read test code)
2. Fix location/name/dependencies of violating classes
3. If exceptions are needed, confirm with user before adding exceptions to ArchUnit rules
4. Re-run ArchUnit tests to confirm pass

### 12. Error Prone Violations

**Symptoms**: `compileJava` failure (with Error Prone plugin integration), compile warnings/errors

**Common violation types**:
| Violation | Fix |
|-----------|-----|
| `NullAway` | Add `@Nullable` annotation, insert null checks |
| `MissingOverride` | Add `@Override` annotation |
| `UnusedVariable` | Remove unused variables |
| `FutureReturnValueIgnored` | Handle return value or explicitly ignore |
| `ImmutableEnumChecker` | Change enum fields to final |

**Resolution protocol**:
1. Check Error Prone check name from compile error message
2. Fix by referencing table above (mostly annotation additions or code pattern changes)
3. If specific check suppression is needed, use `@SuppressWarnings("CheckName")` (minimally)
4. Recompile to confirm pass

---

## General Principles

### Evidence-based Resolution (v2.7)

에러 해결 시 아래 우선순위로 근거를 제시한다:

| 우선순위 | 근거 유형 | 예시 |
|---------|----------|------|
| 1 | 프로젝트 코드베이스 내 성공 사례 | "UserService.kt:23에서 동일 패턴 사용 중" |
| 2 | error-playbook.md 해결 프로토콜 | "§1 Circular Dependency: Port 인터페이스 추출" |
| 3 | references/ 문서 규칙 | "hexagonal-architecture.md § Layer constraints" |
| 4 | 공식 라이브러리 문서 (외부) | "MockK docs: relaxed mock 사용 시 주의사항" |

**권장 규칙**:
- 우선순위 1-3의 근거를 먼저 탐색하고, 충분한 경우 이를 기반으로 해결
- 외부 참조(우선순위 4)는 내부 근거가 불충분할 때 보완적으로 사용
- 근거 없는 추측성 수정은 Prohibited Workarounds와 동일하게 금지

### Halt After 3 Consecutive Failures

When the same approach fails 3 consecutive times, **always halt** and:
1. Record the failure pattern
2. Transition to `Status: blocked` state
3. Report the situation to the user

### Prohibited Workarounds

The following methods for bypassing errors are **prohibited**:
- Overuse of `@Suppress("UNCHECKED_CAST")`
- `as Any` type casting
- Excessive `!!` (non-null assertion)
- `@Disabled` on tests
- Catching and ignoring errors (`catch (e: Exception) {}`)
