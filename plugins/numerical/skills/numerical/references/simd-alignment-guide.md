# SIMD Alignment Guide

> Memory alignment requirements, vectorization patterns, and SIMD optimization for numerical computing

## SIMD Instruction Set Overview

| ISA | Register Width | Alignment Required | float32 per reg | float64 per reg |
|-----|---------------|-------------------|-----------------|-----------------|
| SSE/SSE2 | 128-bit | 16 bytes | 4 | 2 |
| AVX/AVX2 | 256-bit | 32 bytes | 8 | 4 |
| AVX-512 | 512-bit | 64 bytes | 16 | 8 |
| NEON (ARM) | 128-bit | 16 bytes | 4 | 2 |
| SVE (ARM) | 128-2048 bit | varies | varies | varies |

## Memory Alignment

### Alignment Requirements

```
Aligned load/store: Memory address must be a multiple of the register width
  SSE:     address % 16 == 0
  AVX:     address % 32 == 0
  AVX-512: address % 64 == 0

Unaligned load/store:
  - Modern CPUs: Works but slower (especially when crossing cache line boundaries)
  - Older CPUs: May cause SIGBUS/segfault
  - Cache line: 64 bytes on most x86 CPUs
```

### Python/NumPy Alignment

NumPy allocates aligned memory by default (typically 64-byte aligned on modern versions):

```python
# Check alignment
a = np.empty(100, dtype=np.float64)
print(a.ctypes.data % 64)  # Should be 0 for 64-byte alignment

# Force alignment
a = np.require(a, requirements='A')  # 'A' = aligned

# Non-contiguous arrays lose alignment guarantees
b = a[::2]  # Strided view — NOT guaranteed aligned
```

### Dart SIMD Alignment

```dart
// Float32x4 operations require Float32List backing
final list = Float32List(100);  // Platform allocator handles alignment
final simd = list.buffer.asFloat32x4List();  // SIMD view

// ⚠ Offset access may break alignment
final sublist = Float32List.sublistView(list, 1);  // offset=1 → misaligned for SIMD
```

---

## Vectorization Patterns

### Auto-vectorized Operations (NumPy)

These operations are already SIMD-optimized internally:

```python
# Element-wise operations — fully vectorized
np.add(a, b)          # SIMD add
np.multiply(a, b)     # SIMD multiply
np.sqrt(a)            # SIMD sqrt
a + b                 # operator overload → same as np.add

# Reductions — partially vectorized
np.sum(a)             # Pairwise summation (good precision + SIMD)
np.max(a)             # SIMD comparison
np.dot(a, b)          # BLAS (MKL/OpenBLAS) — highly optimized

# Linear algebra — BLAS/LAPACK (external, highly optimized)
np.linalg.solve(A, b)  # LAPACK
np.linalg.svd(A)       # LAPACK
```

### Manual Vectorization Opportunities

Replace Python loops with vectorized operations:

```python
# ❌ Python loop (no SIMD)
result = np.empty(n)
for i in range(n):
    result[i] = a[i] * b[i] + c[i]

# ✅ Vectorized (SIMD-enabled)
result = a * b + c

# ❌ Conditional loop
for i in range(n):
    if a[i] > 0:
        result[i] = a[i]
    else:
        result[i] = 0

# ✅ Vectorized conditional
result = np.where(a > 0, a, 0)
# OR
result = np.maximum(a, 0)  # ReLU pattern

# ❌ Reduction loop
total = 0.0
for x in array:
    total += x * x

# ✅ Vectorized reduction
total = np.dot(array, array)
```

### Dart SIMD Operations

```dart
import 'dart:typed_data';

// SIMD-accelerated element-wise operation
void addFloat32x4(Float32List a, Float32List b, Float32List result) {
  final ax4 = a.buffer.asFloat32x4List();
  final bx4 = b.buffer.asFloat32x4List();
  final rx4 = result.buffer.asFloat32x4List();

  for (var i = 0; i < ax4.length; i++) {
    rx4[i] = ax4[i] + bx4[i];  // 4 additions per instruction
  }

  // Handle remainder elements (if length not multiple of 4)
  final remainder = a.length % 4;
  for (var i = a.length - remainder; i < a.length; i++) {
    result[i] = a[i] + b[i];
  }
}
```

---

## Performance Considerations

### Cache-Friendly Access

```python
# ❌ Column-wise access on C-order array (cache-unfriendly)
a = np.zeros((1000, 1000), order='C')  # Row-major
for j in range(1000):
    for i in range(1000):
        a[i, j] = ...  # Strided access, cache misses

# ✅ Row-wise access on C-order array
for i in range(1000):
    for j in range(1000):
        a[i, j] = ...  # Sequential access, cache-friendly

# ✅ Or use Fortran order for column access
a = np.zeros((1000, 1000), order='F')  # Column-major
```

### Contiguity and SIMD

```python
# ✅ Contiguous array — SIMD-friendly
a = np.ascontiguousarray(input_data)

# ⚠ Non-contiguous view — may prevent SIMD
b = a[:, ::2]  # Every other column — strided
c = a.T        # Transpose of C-order → non-contiguous

# Check contiguity
print(a.flags['C_CONTIGUOUS'])  # True for C-contiguous
print(a.flags['F_CONTIGUOUS'])  # True for Fortran-contiguous
```

### Subnormal Number Performance

Subnormal (denormalized) numbers are extremely small values near the underflow boundary.
Many CPUs handle them 10-100x slower than normal numbers.

```python
# Check for subnormals
has_subnormals = np.any(
    (np.abs(a) > 0) & (np.abs(a) < np.finfo(a.dtype).tiny)
)

# Flush to zero if performance-critical
if has_subnormals:
    a = np.where(np.abs(a) < np.finfo(a.dtype).tiny, 0, a)
```

---

## Verification Checklist

```
□ Arrays passed to C/Fortran extensions are contiguous
□ SIMD operations use properly aligned buffers
□ Strided views are copied before SIMD-intensive operations
□ Cache access patterns match memory layout (row-wise for C-order)
□ Subnormal numbers are handled (flush-to-zero or accept performance cost)
□ Dart Float32x4 operations use Float32List with correct offset alignment
□ Remainder elements handled when array length is not a multiple of SIMD width
```
