# GPU Memory Guide

> GPU memory management, host-device transfer optimization, and common pitfalls

## GPU Memory Hierarchy

```
┌──────────────────────────────┐
│        Host (CPU) RAM        │  Typically 16-256 GB
│  ┌────────────────────────┐  │
│  │    Pinned Memory       │  │  Page-locked, fast DMA transfer
│  └────────────────────────┘  │
└──────────────┬───────────────┘
               │ PCIe Bus (16-64 GB/s)
┌──────────────▼───────────────┐
│        Device (GPU) RAM      │  Typically 8-80 GB
│  ┌────────────────────────┐  │
│  │    Global Memory       │  │  Visible to all threads
│  │  ┌──────────────────┐  │  │
│  │  │  L2 Cache        │  │  │  Shared across SMs
│  │  │  ┌────────────┐  │  │  │
│  │  │  │ L1 / Shared│  │  │  │  Per-SM, fast access
│  │  │  │ Registers  │  │  │  │  Per-thread, fastest
│  │  │  └────────────┘  │  │  │
│  │  └──────────────────┘  │  │
│  └────────────────────────┘  │
└──────────────────────────────┘
```

## Common Memory Patterns

### CuPy (NumPy-compatible GPU arrays)

```python
import cupy as cp

# Allocation
gpu_arr = cp.zeros((1000, 1000), dtype=cp.float32)  # On GPU
gpu_arr = cp.asarray(numpy_arr)                       # CPU → GPU transfer

# Transfer back
cpu_arr = cp.asnumpy(gpu_arr)  # GPU → CPU transfer
cpu_arr = gpu_arr.get()        # Same as above

# Memory pool
pool = cp.get_default_memory_pool()
pool.free_all_blocks()  # Release cached memory
print(pool.used_bytes(), pool.total_bytes())
```

### PyTorch

```python
import torch

# Allocation
t = torch.zeros(1000, 1000, device='cuda')
t = torch.tensor(data, device='cuda')
t = cpu_tensor.to('cuda')       # CPU → GPU
t = cpu_tensor.cuda()           # Same

# Transfer back
cpu_t = gpu_tensor.cpu()        # GPU → CPU
cpu_t = gpu_tensor.to('cpu')    # Same

# Memory management
torch.cuda.empty_cache()        # Release cached memory
print(torch.cuda.memory_allocated())
print(torch.cuda.max_memory_allocated())
```

---

## Common Pitfalls

### 1. Unnecessary Host-Device Transfers

```python
# ❌ Transfer in loop (massive overhead)
for batch in dataloader:
    gpu_data = cp.asarray(batch)  # CPU→GPU every iteration
    result = process(gpu_data)
    cpu_result = cp.asnumpy(result)  # GPU→CPU every iteration
    results.append(cpu_result)

# ✅ Batch transfers, accumulate on GPU
gpu_results = []
for batch in dataloader:
    gpu_data = cp.asarray(batch)
    gpu_results.append(process(gpu_data))

# Single transfer at end
cpu_results = [cp.asnumpy(r) for r in gpu_results]
```

### 2. Computation Graph Retention (PyTorch)

```python
# ❌ Retains computation graph → GPU memory leak
losses = []
for batch in dataloader:
    loss = model(batch)
    losses.append(loss)  # Retains entire graph!

# ✅ Detach scalar values
losses = []
for batch in dataloader:
    loss = model(batch)
    losses.append(loss.item())  # Extracts scalar, releases graph
```

### 3. GPU Memory Fragmentation

```python
# ❌ Variable-size allocations cause fragmentation
for size in varying_sizes:
    temp = torch.zeros(size, device='cuda')
    # ... use temp ...
    del temp

# ✅ Pre-allocate maximum size, use views
max_buffer = torch.zeros(max_size, device='cuda')
for size in varying_sizes:
    temp = max_buffer[:size]  # View, no allocation
    # ... use temp ...
```

### 4. Mixed Precision Pitfalls

```python
# ❌ Manual float16 without loss scaling → gradient underflow
model.half()
loss = criterion(model(input.half()), target)
loss.backward()  # Gradients may underflow to zero

# ✅ Use automatic mixed precision
from torch.cuda.amp import autocast, GradScaler
scaler = GradScaler()
with autocast():
    loss = criterion(model(input), target)
scaler.scale(loss).backward()
scaler.step(optimizer)
scaler.update()
```

### 5. Synchronization Overhead

```python
# ❌ Implicit sync after every operation
for i in range(1000):
    result = gpu_op(data)
    print(result)  # Forces GPU→CPU sync!

# ✅ Async execution, sync only when needed
for i in range(1000):
    result = gpu_op(data)  # Queued, async

torch.cuda.synchronize()  # Single sync at end
print(result)
```

---

## Memory Optimization Strategies

### Strategy 1: Gradient Checkpointing

Trade compute for memory — recompute intermediate activations instead of storing them:

```python
# PyTorch
from torch.utils.checkpoint import checkpoint
output = checkpoint(expensive_layer, input)  # Recomputes in backward pass
```

### Strategy 2: In-place Operations

```python
# ❌ Allocates new tensor
output = input + bias

# ✅ In-place (no allocation)
input.add_(bias)

# ⚠ In-place on leaf tensors with requires_grad raises error
# Use only on intermediate tensors
```

### Strategy 3: Memory-Efficient Attention

```python
# For transformer models, use Flash Attention or memory-efficient attention
# PyTorch 2.0+:
from torch.nn.functional import scaled_dot_product_attention
output = scaled_dot_product_attention(q, k, v)  # Automatically selects best kernel
```

### Strategy 4: Chunked Processing

```python
# Process large arrays in chunks to fit in GPU memory
chunk_size = estimate_chunk_size(available_memory, element_size)
results = []
for i in range(0, len(data), chunk_size):
    chunk = cp.asarray(data[i:i+chunk_size])
    results.append(process(chunk))
    del chunk  # Free GPU memory
    cp.get_default_memory_pool().free_all_blocks()
```

---

## GPU Numerical Considerations

### Non-determinism

GPU operations can be non-deterministic due to:
- Atomic operations in parallel reductions
- cuDNN algorithm selection
- Thread scheduling

```python
# PyTorch: Force deterministic mode (slower but reproducible)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
torch.use_deterministic_algorithms(True)
```

### Precision Differences CPU vs GPU

- GPU float32 operations may use FMA (fused multiply-add), producing slightly different results from CPU
- Reduction order differs (parallel vs sequential), affecting floating-point accumulation
- Some GPU operations use float16 or TF32 internally (NVIDIA Ampere+)

```python
# Disable TF32 for bit-exact float32 results
torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False
```

---

## Verification Checklist

```
□ No unnecessary host-device transfers in loops
□ Computation graphs are detached when not needed for backward
□ Memory is released after use (del + cache clear for CuPy)
□ Batch sizes fit in available GPU memory (profile with torch.cuda.memory_summary())
□ Mixed precision uses proper loss scaling
□ Non-determinism is documented when present
□ Synchronization points are minimized
□ Pre-allocation used for variable-size workloads
```
