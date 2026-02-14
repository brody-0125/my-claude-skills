# Floating-Point Guide

> IEEE 754 fundamentals, precision characteristics, and comparison strategies for numerical computing

## IEEE 754 Representation

### Binary Floating-Point Formats

| Format | Total bits | Sign | Exponent | Mantissa | Decimal digits | Range |
|--------|-----------|------|----------|----------|---------------|-------|
| float16 (half) | 16 | 1 | 5 | 10 | ~3.3 | ±6.5×10⁴ |
| float32 (single) | 32 | 1 | 8 | 23 | ~7.2 | ±3.4×10³⁸ |
| float64 (double) | 64 | 1 | 11 | 52 | ~15.9 | ±1.8×10³⁰⁸ |
| float128 (quad) | 128 | 1 | 15 | 112 | ~34.0 | ±1.2×10⁴⁹³² |

### Machine Epsilon

The smallest representable difference from 1.0:

| Format | Machine Epsilon | Python Constant |
|--------|----------------|-----------------|
| float16 | 9.77×10⁻⁴ | `np.finfo(np.float16).eps` |
| float32 | 1.19×10⁻⁷ | `np.finfo(np.float32).eps` |
| float64 | 2.22×10⁻¹⁶ | `np.finfo(np.float64).eps` |

### Special Values

| Value | Bit Pattern (float64) | Created By | Propagation |
|-------|----------------------|------------|-------------|
| +0.0 | 0x0000000000000000 | Default initialization | `+0 == -0` is True |
| -0.0 | 0x8000000000000000 | Negative underflow | `1/(-0.0)` = `-inf` |
| +Inf | 0x7FF0000000000000 | Overflow, `1/+0` | `inf + x = inf` |
| -Inf | 0xFFF0000000000000 | Overflow, `1/-0` | `-inf + x = -inf` |
| QNaN | 0x7FF8000000000001 | `0/0`, `inf-inf` | NaN op x = NaN |
| SNaN | 0x7FF0000000000001 | Manual creation | Raises exception on use |

**Critical NaN behaviors:**
- `NaN == NaN` → `False` (use `np.isnan()` to test)
- `NaN != NaN` → `True`
- `np.sort()` with NaN: position is undefined (use `np.sort(np.nan_to_num(x))`)
- `np.max()` with NaN: returns NaN (use `np.nanmax()` instead)

---

## Comparison Strategies

### 1. Absolute Tolerance

```python
|actual - expected| <= atol
```

**Use when**: Expected values are near zero.
**Problem**: Does not scale with magnitude of values.

### 2. Relative Tolerance

```python
|actual - expected| <= rtol * |expected|
```

**Use when**: Values span a wide range of magnitudes.
**Problem**: Undefined/unstable when expected ≈ 0.

### 3. Combined Tolerance (Recommended Default)

```python
|actual - expected| <= atol + rtol * |expected|
```

This is what `numpy.testing.assert_allclose` uses.
- `atol` handles the near-zero regime
- `rtol` handles scaling

**Default values (NumPy assert_allclose)**: `rtol=1e-7, atol=0`

### 4. ULP (Unit in the Last Place) Comparison

Measures the number of representable floats between two values:

```python
# Number of ULPs between a and b
np.testing.assert_array_max_ulp(a, b, maxulp=4)
```

**Use when**: Maximum precision is required and you need to reason about the number of representable values between results.

### 5. Choosing Tolerances

| Scenario | Recommended (rtol, atol) |
|----------|-------------------------|
| float64, single operation | `(1e-14, 1e-15)` |
| float64, 10 chained operations | `(1e-12, 1e-13)` |
| float64, matrix ops (N×N) | `(N * 1e-12, N * 1e-13)` |
| float32, single operation | `(1e-6, 1e-7)` |
| float32, neural network forward | `(1e-5, 1e-6)` |
| float16 (half precision) | `(1e-2, 1e-3)` |
| GPU, float32 | `(1e-4, 1e-5)` |
| Iterative solvers | `(solver_tol * 10, solver_tol * 10)` |

**Rule of thumb**: Each chained operation can lose ~1 ULP. For N operations, expect ~√N ULP error (random walk model) or N ULP (worst case).

---

## Common Precision Pitfalls

### Catastrophic Cancellation

Subtracting nearly equal numbers:
```python
# ❌ Loses precision when a ≈ b
result = a - b

# ✅ Restructure to avoid subtraction of similar magnitudes
# For a² - b²:
result = (a + b) * (a - b)

# For variance: E[X²] - (E[X])²
# Use Welford's online algorithm instead
```

### Absorption

Adding a small number to a large number:
```python
# ❌ small gets absorbed into large
total = 0.0
for x in many_small_values:
    total += x  # progressively loses precision

# ✅ Use compensated summation
total = math.fsum(many_small_values)  # Python
total = np.sum(many_small_values)     # NumPy (uses pairwise summation)
```

### Overflow/Underflow

```python
# ❌ Overflow in softmax
probs = np.exp(logits) / np.sum(np.exp(logits))

# ✅ Max-subtraction trick
logits_shifted = logits - np.max(logits)
probs = np.exp(logits_shifted) / np.sum(np.exp(logits_shifted))

# ❌ Underflow in product of probabilities
p = np.prod(probabilities)  # quickly reaches 0

# ✅ Log-space computation
log_p = np.sum(np.log(probabilities))
```

### Stable Alternatives

| Unstable | Stable | Function |
|----------|--------|----------|
| `log(1 + x)` for small x | `math.log1p(x)` | Preserves precision near zero |
| `exp(x) - 1` for small x | `math.expm1(x)` | Preserves precision near zero |
| `sqrt(x² + y²)` | `math.hypot(x, y)` | Avoids overflow |
| `log(sum(exp(x)))` | `scipy.special.logsumexp(x)` | Avoids overflow |

---

## dtype Promotion Rules (NumPy)

When two arrays of different dtypes interact:

```
bool → int8 → int16 → int32 → int64
                                  ↘
uint8 → uint16 → uint32 → uint64 → float64
                                      ↗
         float16 → float32 → float64 → complex128
                                ↗
                        complex64
```

**Key rules:**
- int + float → float (may lose integer precision for large ints in float32)
- float32 + float64 → float64
- Any + complex → complex
- Scalar operations may not promote: `np.float32(1.0) + 1.0` → float64

---

## Dart Floating-Point Notes

Dart uses IEEE 754 double-precision (64-bit) for all `double` values. There is no native float32 type at the language level.

**For SIMD/tensor operations:**
- `Float32List` and `Float64List` from `dart:typed_data`
- `Float32x4` for SIMD operations (4 float32 values packed)
- dart_tensor_preprocessing uses Float32 internally for SIMD acceleration

**Comparison in Dart:**
```dart
// ❌ Direct comparison
expect(actual == expected, isTrue);

// ✅ Tolerance-based comparison
expect(actual, closeTo(expected, 1e-6));
```
