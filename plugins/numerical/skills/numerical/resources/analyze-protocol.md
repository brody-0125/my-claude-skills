# Analyze Protocol

> Phase 1: Numerical operation analysis procedure

> Detailed inspection of numerical operations in the codebase to catalog patterns, identify precision risks, and map data flow.

## Required Reads (skip if already loaded in this session)

> Base Set: see SKILL.md "Context Documents" section (profile, floating-point-guide, language conventions)

**Phase-specific additions:**
- `references/broadcasting-rules.md` (when ndarray/tensor ops detected)
- `references/simd-alignment-guide.md` (when SIMD ops detected or `simd-focus` keyword)
- `references/gpu-memory-guide.md` (when GPU libs detected or `gpu-optimize` keyword)

---

## 1-1. Target Resolution

```
1. IF user specified target file(s): Use those files
2. IF user specified package/module: Glob for files in that path
3. IF no target specified:
   - Find files with numeric library imports:
     Python: Grep for "import numpy|import scipy|import cupy|import torch|from numpy"
     Dart: Grep for "import.*dart_tensor|import.*ml_linalg"
   - Prioritize recently changed files (git diff)
```

## 1-2. dtype Tracking

Track data types through all numeric operations:

```
For each target file:
1. Identify array/tensor creation points:
   Python: np.array(), np.zeros(), np.ones(), torch.tensor(), etc.
   Dart: TensorBuffer.fromUint8List(), TensorBuffer.zeros(), etc.

2. Track dtype through operations:
   - Explicit dtype specifications (dtype=np.float32)
   - Implicit promotions (int + float → float, float32 + float64 → float64)
   - Downcast risks (float64 → float32 assignments)

3. Flag precision risks:
   ⚠ float32 used for accumulation (sum, mean) of many elements
   ⚠ Implicit promotion in mixed-dtype operations
   ⚠ float16 used without loss scaling in training loops
   ⚠ Integer overflow risk in large array indexing (int32 with >2B elements)
```

## 1-3. Shape Analysis

Trace array/tensor shapes through computation:

```
For each target file:
1. Identify shape-defining operations:
   - Array creation with explicit shape
   - reshape(), view(), transpose(), permute()
   - Slicing and indexing operations
   - Concatenation and stacking

2. Build shape flow graph:
   input_shape → operation → output_shape → operation → ...

3. Flag shape risks:
   ⚠ reshape(-1) without shape assertion
   ⚠ Transpose without matching downstream expectations
   ⚠ Dimension mismatch between branches before merge
   ⚠ Broadcasting where explicit expansion was intended
```

## 1-4. Precision Risk Detection

Identify floating-point hazards:

```
Category 1: Catastrophic Cancellation
- Subtraction of nearly-equal values (a - b where a ≈ b)
- Quadratic formula: b² - 4ac where b² ≈ 4ac
- Variance computation: E[X²] - (E[X])² for narrow distributions
- Signal: Variables named *diff*, *delta*, *residual* near subtraction

Category 2: Absorption
- Summation of values with vastly different magnitudes
- Running sum/mean without compensated summation (Kahan)
- Signal: Loop accumulation patterns without numpy.sum()

Category 3: Overflow/Underflow
- exp() on large values without log-space computation
- Product of many small probabilities without log-prob
- Signal: np.exp(), math.exp(), softmax without max-subtraction

Category 4: Comparison Hazards
- Direct == comparison on floating-point results
- Tolerance-free assertions in tests
- Signal: "==" or "!=" operators on float arrays

Category 5: NaN/Inf Propagation
- Division operations without zero-check
- log() on potentially non-positive values
- sqrt() on potentially negative values
- Signal: Missing np.isnan()/np.isinf() guards
```

## 1-5. Broadcasting Pattern Catalog

Map all broadcasting operations:

```
For each broadcasting operation:
1. Record operand shapes: (M, 1) op (1, N) → (M, N)
2. Classify intent:
   - Explicit (np.broadcast_to, expand_dims before op)
   - Implicit (shapes differ, NumPy auto-broadcasts)

3. Flag risks:
   ⚠ Implicit broadcasting where shapes suggest alignment error
   ⚠ Broadcasting (N,) with (N,1) — common source of bugs
   ⚠ Broadcasting scalars with high-dimensional arrays in loops
```

## 1-6. Memory Layout Analysis

Track memory access patterns:

```
1. Identify memory layout specifications:
   - np.array(..., order='C') vs order='F'
   - np.ascontiguousarray(), np.asfortranarray()
   - Tensor memory_format (torch.contiguous_format, torch.channels_last)

2. Track layout through operations:
   - Transpose creates non-contiguous view
   - Slicing may create non-contiguous view
   - Operations requiring contiguous input

3. Flag risks:
   ⚠ Non-contiguous array passed to C extension expecting contiguous
   ⚠ Column-wise iteration on row-major array (cache-unfriendly)
   ⚠ Frequent layout conversions in hot loops
```

## 1-7. Special Value Handling

Check for IEEE 754 special value management:

```
1. NaN handling:
   - Are NaN inputs expected? Is there guard code?
   - Do operations propagate NaN silently?
   - Is np.nan_to_num() used appropriately?

2. Infinity handling:
   - Are overflow results handled?
   - Is np.clip() or saturation used?

3. Signed zero:
   - Does -0.0 vs +0.0 matter for downstream operations?
   - Division by zero producing ±Inf correctly?

4. Subnormal numbers:
   - Performance-sensitive code handling denormals?
   - flush-to-zero (FTZ) mode considerations?
```

---

## Analysis Report Output

→ Template: [templates/analysis-report-template.md](../templates/analysis-report-template.md)

Sections: Project Profile, dtype Usage, Shape Flow, Precision Risks, Broadcasting Operations, Memory Layout Issues, Special Value Gaps, Summary.

---

## Phase Handoff

**Entry Condition**: Phase 0 complete (numeric profile cached)

**Exit Condition**: Analysis report generated with all categories

**Next Phase**: Phase 2 (Verify) — unless `dry-run` mode

**Data Handoff**: Analysis report is used as input for targeted verification in Phase 2
