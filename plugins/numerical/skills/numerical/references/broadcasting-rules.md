# Broadcasting Rules

> Array broadcasting semantics for NumPy, PyTorch, and Dart tensor libraries

## Core Broadcasting Rules (NumPy)

Broadcasting describes how arrays with different shapes are treated during arithmetic operations.

### The Three Rules

1. **Dimension alignment**: If arrays differ in ndim, the shape of the shorter array is padded with 1s **on the left** (leading dimensions).
2. **Dimension compatibility**: Two dimensions are compatible if they are equal, or one of them is 1.
3. **Expansion**: A dimension of size 1 is stretched to match the other array's dimension.

If any dimension pair is incompatible (different sizes, neither is 1), broadcasting fails with `ValueError`.

### Step-by-Step Example

```
Array A: shape (3, 1, 4)
Array B: shape    (5, 4)

Step 1: Pad B with leading 1 → (1, 5, 4)
Step 2: Compare dimensions right-to-left:
  dim 2: 4 == 4 ✓
  dim 1: 1 vs 5 → broadcast A's dim 1 to 5 ✓
  dim 0: 3 vs 1 → broadcast B's dim 0 to 3 ✓
Result: (3, 5, 4)
```

### Quick Reference Table

| Shape A | Shape B | Result | Valid? |
|---------|---------|--------|--------|
| (3,) | (3,) | (3,) | ✓ |
| (3,) | (1,) | (3,) | ✓ |
| (3, 4) | (4,) | (3, 4) | ✓ |
| (3, 4) | (3, 1) | (3, 4) | ✓ |
| (3, 4) | (1, 4) | (3, 4) | ✓ |
| (3, 1) | (1, 4) | (3, 4) | ✓ outer product style |
| (3,) | (4,) | — | ✗ incompatible |
| (3, 4) | (3,) | — | ✗ trailing dim 4≠3 |
| (2, 3, 4) | (3, 4) | (2, 3, 4) | ✓ |
| (2, 1, 4) | (3, 1) | (2, 3, 4) | ✓ |

---

## Common Broadcasting Bugs

### Bug 1: (N,) vs (N, 1) Confusion

```python
a = np.array([1, 2, 3])       # shape (3,)
b = np.array([[1], [2], [3]])  # shape (3, 1)

# These produce DIFFERENT results:
a + b  # (3,) + (3,1) → (1,3) + (3,1) → (3,3) outer-product style!
# NOT element-wise addition

# ✅ For element-wise: ensure same shape
a + b.ravel()  # (3,) + (3,) → (3,)
# OR
a[:, np.newaxis] + b  # (3,1) + (3,1) → (3,1)
```

### Bug 2: Silent Broadcasting

```python
# Intended: element-wise multiply of same-shaped arrays
weights = np.random.randn(10, 1)    # accidentally (10, 1) not (10, 5)
features = np.random.randn(10, 5)   # shape (10, 5)

result = weights * features  # silently broadcasts to (10, 5)!
# Each weight row is replicated across all 5 feature columns
# This may NOT be the intended behavior

# ✅ Add shape assertion
assert weights.shape == features.shape, f"Shape mismatch: {weights.shape} vs {features.shape}"
```

### Bug 3: Scalar Broadcasting in Loops

```python
# ❌ Broadcasts scalar to full array each iteration
for i in range(1000):
    result += scalar * large_array  # scalar is broadcast every time

# ✅ Pre-multiply
scaled_array = scalar * large_array
for i in range(1000):
    result += scaled_array
```

### Bug 4: Batch Dimension Mismatch

```python
# Model expects batch dimension, single input doesn't have it
model_weights = np.random.randn(32, 10)  # (batch, features)
single_input = np.random.randn(10)        # (features,) — missing batch dim

result = model_weights @ single_input  # works but may not be what you want
# single_input is treated as (10, 1) for matmul → result is (32,)

# ✅ Explicit batch handling
single_input = single_input[np.newaxis, :]  # (1, 10)
result = single_input @ model_weights.T      # (1, 32) → clear batch semantics
```

---

## Broadcasting Verification Checklist

When reviewing broadcasting operations:

```
□ Both operand shapes are known (not dynamic/unknown)
□ The result shape matches mathematical expectation
□ No unintended dimension expansion (assert shapes before operation)
□ Scalar operations are intentional (not accidentally reduced arrays)
□ Batch dimensions are consistently positioned (batch-first or batch-last)
□ When shapes differ, the broadcasting intent is documented in comments
```

---

## PyTorch Broadcasting

PyTorch follows the same broadcasting rules as NumPy with these additions:

- `torch.broadcast_to(tensor, shape)` — explicit broadcasting
- `tensor.expand(shape)` — lazy broadcasting (no memory allocation)
- `tensor.repeat(repeats)` — explicit data replication (allocates memory)

**Prefer `expand()` over `repeat()`** when broadcasting is sufficient (no data copy needed).

---

## Dart Tensor Broadcasting

dart_tensor_preprocessing broadcasting:

- Follows NumPy-compatible broadcasting rules
- Element-wise operations (`add`, `multiply`, etc.) support broadcasting
- Shape validation happens at runtime; verify shapes in tests

```dart
// Broadcasting in dart_tensor_preprocessing
final a = TensorBuffer.fromList([1.0, 2.0, 3.0], shape: [3, 1]);
final b = TensorBuffer.fromList([4.0, 5.0], shape: [1, 2]);
final result = a.multiply(b);  // shape: [3, 2]
```

---

## Explicit Broadcasting Functions

When broadcasting intent must be clear, use explicit functions:

```python
# NumPy
np.broadcast_to(a, target_shape)    # read-only view
np.broadcast_shapes(shape1, shape2)  # compute result shape without operation
np.expand_dims(a, axis=0)           # add dimension

# PyTorch
torch.broadcast_to(t, target_shape)
t.expand(target_shape)               # lazy, no copy
t.unsqueeze(dim)                     # add dimension
```
