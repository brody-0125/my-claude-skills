# Verification Tiers

> A protocol that automatically adjusts the verification level based on the computational complexity and scope of changes

## Tier Determination Criteria

| Tier | Condition | Verification Scope |
|------|-----------|-------------------|
| **LIGHT** | Changed files ≤ 3 AND single numeric operation type | Basic precision + shape checks |
| **STANDARD** | 4 ≤ files ≤ 15 OR multi-operation types (default) | Full 7-category checklist |
| **THOROUGH** | Changed files ≥ 16 OR GPU code OR native extensions OR `precision-focus` | Full checklist + test execution + sub-agent review |

### Minimum Tier Guarantee

- When loop is specified, **minimum STANDARD** is applied
- `precision-focus` keyword forces **minimum THOROUGH**
- GPU operations force **minimum STANDARD**

## Tier Auto-determination Logic

```
1. Count changed files: git diff --name-only -- '*.py' '*.dart' '*.pyx' | wc -l
2. Classify numeric operation types:
   - array-creation, broadcasting, linear-algebra, fft, random, reduction, indexing
3. Check complexity indicators:
   - GPU code (cuda, cupy, torch.device)
   - Native extensions (.pyx, .c, .f90 in project)
   - Custom SIMD code
4. Determine Tier:
   - Files ≥ 16 OR GPU code OR native extensions → THOROUGH
   - Files ≤ 3 AND single op type → LIGHT
   - Otherwise → STANDARD
```

---

## LIGHT Tier

### Applicable Targets
- Single function precision fix
- Adding tolerance to existing test
- Simple dtype correction
- Documentation-only changes to numeric code

### Verification Items
```
□ Floating-point comparison checks (no bare ==)
□ dtype consistency in changed operations
□ Test assertion tolerance present and reasonable
□ LLM direct review: precision risk in changed code
```

### Script Execution
```bash
verify-numeric.sh {changed file path} summary
```

---

## STANDARD Tier

### Applicable Targets
- New numeric function implementation
- Broadcasting operation changes
- Test suite additions for numeric code
- Refactoring numeric computation

### Verification Items
Full 7-category checklist:
1. Floating-point correctness
2. Broadcasting compliance
3. Shape consistency
4. Test case integrity
5. Memory safety
6. Special value handling
7. Performance correctness (basic)

### Script Execution
```bash
verify-numeric.sh {project root} detailed
```

**Static analysis:**
```
Python:
  □ ruff check --select E,W,NPY (NumPy linting)
  □ mypy (type checking)
  □ python -m pytest -x (test execution, stop on first failure)

Dart:
  □ dart analyze
  □ dart test
```

---

## THOROUGH Tier

### Applicable Targets
- GPU kernel implementation
- Native C/Fortran extension code
- Cross-library numeric pipeline (NumPy → SciPy → CuPy)
- Precision-critical algorithms (financial, scientific, medical)
- Large-scale refactoring of numeric code

### Verification Items
All of STANDARD + additional:

**Python:**
```
□ python -m pytest --tb=long (full test execution with verbose output)
□ ruff check --select ALL (comprehensive linting)
□ mypy --strict (strict type checking)
□ hypothesis tests pass (if property tests exist)
□ Cross-reference verification for all changed numeric functions
□ Sub-agent precision review (numerical analysis perspective)
```

**Dart:**
```
□ dart analyze --fatal-infos (strict analysis)
□ dart test (full test suite)
□ Cross-reference verification for all changed numeric operations
□ Sub-agent precision review
```

### Sub-agent Review Protocol

In the THOROUGH Tier, a separate review sub-agent is spawned:

```
Review agent input:
- List of changed files (git diff --name-only)
- references/floating-point-guide.md (always)
- references/broadcasting-rules.md (if array ops)
- references/simd-alignment-guide.md (if SIMD)
- references/gpu-memory-guide.md (if GPU)

Review perspectives:
1. Whether floating-point operations maintain precision guarantees
2. Whether broadcasting operations match documented mathematical semantics
3. Whether test assertions are mathematically valid
4. Whether GPU/SIMD code preserves numerical equivalence with CPU path
5. Whether error bounds are correctly documented
```

---

## Tier × Model Routing

검증 티어에 따라 권장 모델을 자동으로 선택하여 비용과 성능을 최적화한다.

| Verification Tier | 권장 Model | 근거 | 예상 비용 절감 |
|-------------------|-----------|------|---------------|
| **LIGHT** | `haiku` | 3파일 이하, 단순 정밀도 검증 — 속도 우선 | 기준 대비 -80% |
| **STANDARD** | `sonnet` | 기본 7-카테고리 검증 — 균형 | 기준 (baseline) |
| **THOROUGH** | `opus` | GPU/네이티브, 정밀도 분석 — 정밀도 우선 | 기준 대비 +200% |

### 자동 에스컬레이션 규칙

```
시작: LIGHT (haiku)
  │
  ├── 정밀도 위반 발견 (catastrophic cancellation, overflow)
  │   └── → STANDARD로 승격 (sonnet)
  │
  ├── GPU 코드 감지 또는 네이티브 확장
  │   └── → THOROUGH로 승격 (opus)
  │
  ├── 동일 위반 2회 연속
  │   └── → 한 단계 승격
  │
  └── Domain 키워드 사용 (`precision-focus`)
      └── → THOROUGH 강제 적용
```

**주의:** 에스컬레이션 후에는 디에스컬레이션하지 않음. 한 번 THOROUGH로 승격되면 해당 세션에서 유지.
