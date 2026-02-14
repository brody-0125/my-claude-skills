# Verify Protocol

> Phase 2: Numerical correctness verification procedure

> Validates floating-point correctness, broadcasting compliance, test case integrity, and edge case coverage.
> Uses Analysis Report from Phase 1 as input for targeted verification.

## Required Reads (skip if already loaded in this session)

> Base Set: see SKILL.md "Context Documents" section (profile, floating-point-guide, language conventions)

**Phase-specific additions:**
- `resources/verification-tiers.md` (for tier determination)
- `resources/error-playbook.md` (when violations are found)
- `references/broadcasting-rules.md` (when broadcast issues found in Analysis)

---

## 2-0. Verify Preparation

```
1. Check previous Verify snapshot: ~/.claude/cache/numerical-{hash}-verify-snapshot.json
   - If exists: Reference previous violation count and timestamp to assess improvement
   - If not: Treat as first verification
2. From Loop 2 onward, switch to incremental verification:
   - scripts/verify-numeric.sh [target path] [output format] --changed-only
   - Only verify files modified in the previous loop
3. Loop 1 or standalone verify: Full verification (default mode)
4. **Context Health Check** (Loop 2+ 시작 시):
   - 컨텍스트 사용량 70% 이상 → WARNING 출력
   - 80% 이상 → `/compact` 권장 메시지 출력
   - 85% 이상 → 즉시 `/compact` 실행 필수
```

## 2-1. Verification Checklist (7 categories)

Items automatically checked by `scripts/verify-numeric.sh` do not require manual verification.
Items marked **(LLM)** require reading the changed files directly.

### Category 1: Floating-Point Correctness

```
□ No direct == comparison on floating-point results
□ Test assertions use appropriate tolerance (atol/rtol)
□ Accumulation operations use numerically stable algorithms
□ No implicit precision loss from dtype demotion
□ (LLM) Catastrophic cancellation patterns addressed
□ (LLM) Overflow/underflow risk mitigated (log-space, clipping)
```

### Category 2: Broadcasting Compliance

```
□ All broadcasting operations have matching trailing dimensions
□ No unintentional broadcasting (shape assertion before operation)
□ (LLM) Broadcasting intent matches documented behavior
□ (LLM) Scalar-array operations are intentional, not shape errors
```

### Category 3: Shape Consistency

```
□ reshape() calls have matching element counts
□ Matrix multiplication dimensions are compatible
□ Concatenation/stacking dimensions are aligned
□ (LLM) Shape transformations maintain semantic meaning
```

### Category 4: Test Case Integrity

```
□ Test expected values have sufficient precision digits
□ Tolerance values are appropriate for the operation
  - Linear algebra: rtol=1e-10, atol=1e-12 (float64); rtol=1e-5, atol=1e-6 (float32)
  - FFT: rtol=1e-10, atol=1e-12 (float64); rtol=1e-5, atol=1e-6 (float32)
  - Neural network forward: rtol=1e-5, atol=1e-6 (float32)
  - GPU operations: rtol=1e-4, atol=1e-5 (float32 + nondeterminism)
  - See error-playbook.md Section 1 for complete tolerance table
□ Edge cases are tested (empty array, single element, NaN input, Inf input)
□ (LLM) Expected values are mathematically correct (cross-check)
□ (LLM) Test covers boundary conditions for dtype ranges
```

### Category 5: Memory Safety

```
□ No out-of-bounds indexing in array operations
□ View vs copy semantics are respected (no unintended mutation)
□ Buffer lifecycle is correct (no use-after-free in native extensions)
□ (LLM) Zero-copy operations don't violate downstream expectations
```

### Category 6: Special Value Handling

```
□ NaN inputs produce documented behavior (propagate, raise, or handle)
□ Infinity results are handled (clip, raise, or document)
□ Division-by-zero paths are guarded
□ (LLM) Subnormal number handling is consistent with performance targets
```

### Category 7: Performance Correctness (STANDARD/THOROUGH)

```
□ SIMD-eligible operations use aligned memory
□ GPU kernel launches have appropriate grid/block dimensions
□ No unnecessary host-device transfers in hot paths
□ (LLM) Parallelization preserves numerical determinism or documents non-determinism
```

## 2-2. Test Verification Sub-protocol

When `test-verify` keyword is used or test files are in scope:

```
For each test file:
1. Extract test cases with numeric assertions:
   - assert_allclose(actual, expected, rtol, atol)
   - assert_array_equal(actual, expected)
   - np.testing.assert_*
   - pytest.approx()
   - Dart: expect(actual, closeTo(expected, delta))

2. For each assertion, verify:
   a. Mathematical correctness of expected value
      - Re-derive from inputs using reference implementation
      - Cross-check with alternate computation path
   b. Tolerance appropriateness
      - float64 operations: rtol >= 1e-15 (machine epsilon)
      - float32 operations: rtol >= 1e-7
      - Accumulated operations: rtol scales with sqrt(N) or N
   c. Edge case coverage
      - Zero inputs
      - Negative inputs (for operations with domain restrictions)
      - Very large / very small values
      - NaN / Inf inputs
      - Empty arrays
      - Single-element arrays

3. Generate verification report:
   | Test | Assertion | Expected | Tolerance | Status | Notes |
   |------|-----------|----------|-----------|--------|-------|
```

## 2-3. Verification Result Output

**Format rules:**
- `Passed: X/Y` means "X checks passed out of Y total checks"
- `Fix` column must use imperative verb form

```markdown
## Verify Results [Loop 1/3] — STANDARD

### Passed: 12/15 items
### Violations: 3 items

| # | Category | Violation | File:Line | Description | Fix |
|---|----------|-----------|-----------|-------------|-----|
| 1 | Precision | Catastrophic cancel | solver.py:45 | a-b where a≈b | Use compensated formula |
| 2 | Broadcasting | Shape mismatch | ops.py:112 | (3,1) * (4,) | Add explicit broadcast_to() |
| 3 | Test | Loose tolerance | test_fft.py:30 | rtol=1e-3 for float64 FFT | Tighten to rtol=1e-10 |

### Auto-fix
Fixing the above violations...

### Fix Complete Summary
- Fixed: 2 items
- Remaining violations: 1 item (requires user decision: solver.py:45)
```

## 2-4. Loop Convergence Failure Handling

**Violation history tracking:**
The verify-snapshot.json accumulates all loop results. At the start of each loop (2+):
1. Read the snapshot file to get the history array
2. Compare current violations with previous loops
3. Track consecutive identical violations

| Consecutive identical failure count | Response |
|--------------------------------------|----------|
| 1st | Normal fix attempt |
| 2nd | Change approach (alternative algorithm, different precision strategy) |
| 3rd | Spawn root cause analysis sub-agent |

**Root cause analysis agent protocol:**
1. Identify whether the issue is fundamental (algorithm limitation) or implementation (fixable)
2. For precision issues: propose alternative formulations (e.g., log-sum-exp instead of direct softmax)
3. For shape issues: trace full shape provenance to find the design error
4. Report to user and await direction

## 2-5. Static Analysis Execution (STANDARD/THOROUGH)

**Python:**
```
□ ruff check --select E,W,NPY (NumPy-specific rules)
□ mypy (type checking for numeric operations)
□ python -m pytest --tb=short (test execution)
```

**Dart:**
```
□ dart analyze (static analysis)
□ dart test (test execution)
```

---

## Phase Handoff

**Entry Condition**: Phase 1 Analyze complete (analysis report generated)

**Exit Condition**: Loop convergence (0 violations) OR max loops reached

**Next Phase**: Phase 3 (Optimize) OR session end

**Domain Keyword Effects**:
- `precision-focus`: ULP comparison 활성화, tolerance 검증 강화
- `broadcast-check`: 모든 broadcasting 연산에 shape assertion 요구
- `test-verify`: 테스트 기댓값 수학적 검증 수행
- `stability`: 조건수(condition number) 분석 포함
