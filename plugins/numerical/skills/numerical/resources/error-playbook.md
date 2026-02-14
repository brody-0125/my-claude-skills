# Error Playbook

> Resolution protocols for frequently occurring numerical computing error types

## Quick Index (에러 시그니처 → 섹션)

| 에러 시그니처 | 섹션 | 키워드 |
|-------------|------|--------|
| `AssertionError: Not equal to tolerance` | [1. Tolerance Mismatch](#1-tolerance-mismatch) | 허용오차 |
| `ValueError: shapes not aligned` | [2. Shape Mismatch](#2-shape-mismatch) | 형상 불일치 |
| `ValueError: could not broadcast` | [3. Broadcasting Error](#3-broadcasting-error) | 브로드캐스팅 |
| `FloatingPointError`, `RuntimeWarning: overflow` | [4. Overflow/Underflow](#4-overflowunderflow) | 오버플로 |
| `nan`, `inf` in results | [5. NaN/Inf Propagation](#5-naninf-propagation) | NaN 전파 |
| `TypeError: dtype mismatch` | [6. dtype Mismatch](#6-dtype-mismatch) | 타입 불일치 |
| `MemoryError`, `CUDA out of memory` | [7. Memory Exhaustion](#7-memory-exhaustion) | 메모리 부족 |
| `Segmentation fault` in native extension | [8. Native Extension Crash](#8-native-extension-crash) | 네이티브 크래시 |
| Loss of significance in subtraction | [9. Catastrophic Cancellation](#9-catastrophic-cancellation) | 자릿수 소실 |
| 동일 위반 3회 반복 | [10. Repeated Violations](#10-repeated-violations) | 수렴 실패 |
| `CUDA error`, GPU kernel failure | [11. GPU Errors](#11-gpu-errors) | GPU 에러 |
| Dart `RangeError`, `FormatException` | [12. Dart Tensor Errors](#12-dart-tensor-errors) | Dart 에러 |

---

## When to Use

Reference this document when the same error repeats during the Verify loop, or when numerical test failures occur.

---

## Error Type-specific Responses

### 1. Tolerance Mismatch

**Symptoms**: `AssertionError: Not equal to tolerance rtol=X, atol=Y`, `assert_allclose` failure

**Root cause analysis order**:
1. Check if tolerance is appropriate for the operation type and dtype
2. Check if expected value is mathematically correct
3. Check if algorithm introduces more error than expected

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Tolerance too tight for float32 | Relax: rtol=1e-5, atol=1e-6 for float32; rtol=1e-10, atol=1e-12 for float64 |
| Expected value imprecise | Re-derive with higher precision (mpmath) or from reference implementation |
| Algorithm instability | Switch to numerically stable formulation (see [9. Catastrophic Cancellation](#9-catastrophic-cancellation)) |
| GPU non-determinism | Add rtol=1e-4 for GPU tests, document non-determinism |
| Accumulated error | Scale tolerance with sqrt(N) for N-element operations |

**Recommended tolerance values by operation:**
| Operation | float32 (rtol, atol) | float64 (rtol, atol) |
|-----------|---------------------|---------------------|
| Element-wise arithmetic | 1e-6, 1e-7 | 1e-14, 1e-15 |
| Matrix multiplication | 1e-5, 1e-6 | 1e-10, 1e-12 |
| FFT | 1e-5, 1e-6 | 1e-10, 1e-12 |
| SVD/Eigendecomposition | 1e-4, 1e-5 | 1e-8, 1e-10 |
| Iterative solver | 1e-3, 1e-4 | 1e-6, 1e-8 |
| GPU operations | 1e-4, 1e-5 | 1e-6, 1e-8 |

### 2. Shape Mismatch

**Symptoms**: `ValueError: shapes (X,) and (Y,) not aligned`, `matmul: dimension mismatch`

**Root cause analysis order**:
1. Print shapes at operation point: `print(f"{a.shape=}, {b.shape=}")`
2. Trace shape backwards to creation/transformation point
3. Check for off-by-one in reshape/transpose

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Missing transpose | Add `.T` or `np.transpose()` before matmul |
| Reshape element count mismatch | Verify `np.prod(old_shape) == np.prod(new_shape)` |
| Batch dimension missing | Add `np.expand_dims()` or `array[np.newaxis, ...]` |
| Wrong axis in concatenation | Change `axis` parameter in `np.concatenate()` |

### 3. Broadcasting Error

**Symptoms**: `ValueError: operands could not be broadcast together with shapes (X,Y) (Z,W)`

**Root cause analysis order**:
1. Print both operand shapes
2. Apply broadcasting rules: trailing dimensions must match or one must be 1
3. Determine intended operation

**Broadcasting rules**: See [broadcasting-rules.md](../references/broadcasting-rules.md) for complete rules and common bugs.

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Missing dimension expansion | Add `np.expand_dims()` or `[:, np.newaxis]` |
| Transposed operand | Transpose one operand to align dimensions |
| Fundamentally incompatible | Redesign operation (loop, explicit indexing) |

### 4. Overflow/Underflow

**Symptoms**: `RuntimeWarning: overflow encountered`, `inf` in result, `0.0` where non-zero expected

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| exp() on large values | Use log-space: `log_softmax = x - logsumexp(x)` |
| Product of small values | Use log-space: `log_prob = sum(log(p_i))` |
| Large integer indexing (int32) | Use int64 for array sizes > 2^31 |
| Intermediate overflow | Break into sub-expressions, use `np.clip()` |

**Stable formulations:**
```python
# ❌ Unstable softmax
softmax = np.exp(x) / np.sum(np.exp(x))

# ✅ Stable softmax (max-subtraction trick)
x_max = np.max(x)
softmax = np.exp(x - x_max) / np.sum(np.exp(x - x_max))

# ❌ Unstable log-sum-exp
lse = np.log(np.sum(np.exp(x)))

# ✅ Stable log-sum-exp
from scipy.special import logsumexp
lse = logsumexp(x)
```

### 5. NaN/Inf Propagation

**Symptoms**: Unexpected `nan` or `inf` values in results

**Root cause analysis order**:
1. Add `np.seterr(all='raise')` to find the first problematic operation
2. Check for 0/0, inf-inf, 0*inf producing NaN
3. Check for log(0), log(negative), sqrt(negative)

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| log(0) | Use `np.log(x + epsilon)` or `np.log1p(x)` |
| 0/0 | Add `np.where(denominator != 0, num/denom, 0.0)` |
| sqrt(negative) | Add `np.clip(x, 0, None)` before sqrt |
| inf - inf | Restructure to avoid; use L'Hopital's rule analytically |
| NaN input data | Add `np.nan_to_num()` or validate inputs early |

### 6. dtype Mismatch

**Symptoms**: `TypeError`, unexpected precision loss, silent truncation

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Mixed float32/float64 | Explicit `.astype(np.float64)` at boundaries |
| Integer division | Use `//` for int, `/` promotes to float |
| Complex from real ops | Check for negative values before sqrt, even roots |
| Dart: int vs double | Use `.toDouble()` explicitly |

### 7. Memory Exhaustion

**Symptoms**: `MemoryError`, `CUDA out of memory`, system OOM kill

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Array too large for RAM | Use chunked processing (dask, generators) |
| GPU batch too large | Reduce batch size, use gradient accumulation |
| Retained computation graph | Call `.detach()` or `.item()` on loss tensors |
| Memory fragmentation | Use `torch.cuda.empty_cache()`, pre-allocate buffers |
| Intermediate arrays | Use in-place operations (`out=` parameter) |

### 8. Native Extension Crash

**Symptoms**: `Segmentation fault`, bus error, SIGABRT in C/Fortran extensions

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Non-contiguous array to C function | Add `np.ascontiguousarray()` before call |
| Wrong dtype to C function | Add explicit dtype cast matching C type |
| Out-of-bounds in C indexing | Add bounds checking, validate array sizes |
| Alignment issue for SIMD | Use `np.require(arr, requirements='A')` for aligned |
| Fortran column-major expected | Use `np.asfortranarray()` or `order='F'` |

### 9. Catastrophic Cancellation

**Symptoms**: Loss of significant digits, unexpectedly large relative error

**Resolution protocol**: See [floating-point-guide.md § Common Precision Pitfalls](../references/floating-point-guide.md) for full stable alternatives table.

Common patterns:
| Pattern | Stable Alternative |
|---------|-------------------|
| `a*a - b*b` | `(a+b) * (a-b)` |
| `E[X²] - E[X]²` | Welford's online algorithm |
| `sqrt(a² + b²)` | `math.hypot(a, b)` |

### 10. Repeated Violations

**Symptoms**: Same numerical issue repeats 3 consecutive times in Verify loop

**3-Strike Escalation:**

| Strike | Response |
|--------|----------|
| 1st | Normal fix (code patch, tolerance adjustment) |
| 2nd | Change approach (alternative algorithm, higher precision dtype) |
| 3rd | **Halt** — spawn root cause analysis sub-agent |

**Root cause analysis procedure:**
1. Collect recurring violation patterns with full context
2. Determine if the issue is:
   - **Fundamental**: Algorithm cannot achieve desired precision → user must choose: relax tolerance or change algorithm
   - **Implementation**: Fixable with different code approach → propose alternative
3. Search for reference implementations in NumPy/SciPy source
4. Present alternatives and await user decision

### 11. GPU Errors

**Symptoms**: `CUDA error`, `cuDNN error`, GPU kernel launch failure

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| CUDA OOM | Reduce batch size, enable gradient checkpointing |
| Device mismatch | Ensure all tensors on same device (`tensor.to(device)`) |
| CUBLAS error | Check matrix dimensions, ensure inputs are 2D |
| Non-deterministic result | Set `torch.backends.cudnn.deterministic = True` |
| Driver incompatibility | Check CUDA toolkit version matches driver |

### 12. Dart Tensor Errors

**Symptoms**: `RangeError`, `FormatException`, shape assertion failure in Dart tensor operations

**Resolution protocol**:
| Cause | Resolution |
|-------|------------|
| Index out of range | Validate indices against `shape` before access |
| Invalid reshape | Verify element count matches: `shape.reduce(*)` |
| SIMD type mismatch | Use `Float32x4` only with `Float32List` backing |
| Isolate memory issue | Use `TransferableTypedData` for cross-isolate transfer |
| Pipeline type error | Verify input dtype matches pipeline preset expectations |

---

## General Principles

### Halt After 3 Consecutive Failures

When the same approach fails 3 consecutive times, **always halt** and:
1. Record the failure pattern
2. Transition to `Status: blocked` state
3. Report the situation to the user

### Prohibited Workarounds

The following methods for bypassing errors are **prohibited**:
- Silencing NumPy warnings (`np.seterr(all='ignore')`) without documented justification
- Blanket `try/except` around numeric operations
- Using `float('inf')` as tolerance
- Replacing NaN with arbitrary values without documentation
- Suppressing test failures with `@pytest.mark.skip` or `@unittest.skip`
- Using `atol=1` or similar absurdly loose tolerances
