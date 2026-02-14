# Optimize Protocol

> Phase 3: Performance and numerical optimization procedure

> Generates optimization suggestions based on Analysis (Phase 1) and Verification (Phase 2) results.
> Covers SIMD vectorization, GPU memory management, memory layout optimization, and algorithmic stability improvements.

## Required Reads (skip if already loaded in this session)

> Base Set: see SKILL.md "Context Documents" section (profile, floating-point-guide, language conventions)

**Phase-specific additions:**
- `references/simd-alignment-guide.md` (always in this phase)
- `references/gpu-memory-guide.md` (when GPU support detected)

---

## 3-1. SIMD Optimization Analysis

### Vectorization Opportunity Detection

```
For each numeric hot path:
1. Identify loop patterns over arrays:
   Python: for-loops over ndarray elements, list comprehensions on numeric data
   Dart: for-loops over List<double>/Float32List

2. Check vectorization status:
   - Already vectorized: np.add(), np.multiply(), element-wise operations
   - Partially vectorized: Mixed loop + vectorized calls
   - Not vectorized: Pure Python/Dart loops over elements

3. Suggest vectorization:
   | Pattern | Current | Suggested | Speedup Estimate |
   |---------|---------|-----------|-----------------|
   | Element-wise loop | for i: a[i]+b[i] | np.add(a, b) | 10-100x |
   | Conditional | [x if c else y for ...] | np.where(c, x, y) | 10-50x |
   | Accumulation | sum in loop | np.sum(a) | 10-100x |
   | Custom reduction | loop with reduce | np.ufunc.reduce | 5-50x |
```

### Memory Alignment

```
1. Check allocation alignment:
   - np.empty() default alignment (usually 64-byte on modern NumPy)
   - Custom allocators (np.require with alignment)
   - Dart: Float32List alignment via typed_data

2. Flag alignment issues:
   ⚠ Arrays passed to BLAS/LAPACK not guaranteed contiguous
   ⚠ Custom C extensions assuming specific alignment
   ⚠ SIMD intrinsics requiring 16/32/64-byte alignment

3. Suggest fixes:
   - np.ascontiguousarray() before C extension calls
   - aligned_alloc wrappers for custom allocators
   - Dart: ensure Float32List backing for SIMD operations
```

## 3-2. GPU Optimization Analysis

### Memory Management

```
1. Identify GPU memory patterns:
   - Allocation: cupy.empty(), torch.zeros(..., device='cuda')
   - Transfer: cupy.asarray(np_array), tensor.to('cuda')
   - Deallocation: explicit free, garbage collection reliance

2. Flag issues:
   ⚠ Unnecessary CPU→GPU→CPU round-trips
   ⚠ Large allocations inside loops (allocate once, reuse)
   ⚠ Missing torch.no_grad() in inference paths
   ⚠ Computation graph retention (loss.item() vs loss)
   ⚠ No memory pool / stream management

3. Optimization suggestions:
   | Pattern | Issue | Suggestion |
   |---------|-------|-----------|
   | Transfer in loop | Repeated host-device copy | Batch transfer outside loop |
   | Large intermediate | GPU OOM risk | Use checkpointing or chunking |
   | No mixed precision | Excessive memory use | Enable AMP (torch.cuda.amp) |
   | Sync after every op | Pipeline stall | Use async transfers, CUDA streams |
```

### Kernel Optimization (when custom kernels detected)

```
1. Grid/block dimension analysis:
   - Block size multiple of warp size (32 for NVIDIA)?
   - Grid covers full data extent?
   - Occupancy considerations?

2. Memory access pattern:
   - Coalesced global memory access?
   - Shared memory bank conflicts?
   - Register pressure?
```

## 3-3. Memory Layout Optimization

```
1. Access pattern analysis:
   - Row-wise iteration on C-order arrays ✓
   - Column-wise iteration on C-order arrays ✗ (suggest F-order or transpose)
   - Strided access patterns (suggest contiguous copy if repeated)

2. Cache efficiency:
   - Working set fits in L1/L2 cache?
   - Tiling/blocking for large matrix operations?
   - Prefetch hints for predictable access patterns?

3. Layout conversion costs:
   - Minimize np.ascontiguousarray() / np.asfortranarray() in loops
   - Choose layout matching dominant access pattern
   - Consider channels-last format for image processing (PyTorch)

4. Zero-copy optimization (Dart):
   - TensorBuffer view operations instead of copy
   - Buffer pool utilization for repeated allocations
   - Isolate-safe buffer sharing
```

## 3-4. Algorithmic Stability Optimization

```
1. Numerically stable alternatives:
   → Full table: references/floating-point-guide.md § "Precision Pitfalls and Stable Alternatives"
   Key patterns: softmax max-subtraction, Kahan summation, math.log1p, math.expm1, Welford's algorithm

2. Condition number awareness:
   - Flag matrix operations on ill-conditioned matrices
   - Suggest SVD-based pseudoinverse instead of direct inverse
   - Recommend condition number check before solve()

3. Error propagation estimation:
   - Forward error analysis for critical computation paths
   - Backward stability verification for iterative algorithms
```

## 3-5. Parallelization Optimization

```
1. Python parallelization:
   - NumPy: Already uses MKL/OpenBLAS threading for BLAS operations
   - Manual: multiprocessing.Pool for embarrassingly parallel tasks
   - Advanced: Dask for out-of-core and distributed computation
   - GPU: CuPy for drop-in NumPy replacement on GPU

2. Dart parallelization:
   - Isolate-based computation for heavy operations
   - SIMD via Float32x4 operations
   - Platform channels for native library delegation

3. Determinism considerations:
   - Document non-deterministic operations (GPU atomics, parallel reduction)
   - Provide deterministic fallback option
   - Seed management for reproducibility
```

---

## Optimization Report Output

→ Template: [templates/optimization-report-template.md](../templates/optimization-report-template.md)

Sections: Summary, SIMD/Vectorization, GPU Optimization, Memory Layout, Numerical Stability, Parallelization, Implementation Priority.

---

## Phase Handoff

**Entry Condition**: Phase 2 Verify complete

**Exit Condition**: Optimization report delivered

**Next Phase**: Session end OR new task cycle

**Domain Keyword Effects**:
- `gpu-optimize`: GPU 섹션 심층 분석, 커널 수준 최적화 포함
- `simd-focus`: SIMD 정렬/벡터화 분석 강화
- `memory-layout`: 캐시 효율성 분석 포함
- `stability`: 수치 안정성 대안 최우선 제안
