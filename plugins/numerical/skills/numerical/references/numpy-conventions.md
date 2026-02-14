# NumPy/Python Numerical Conventions

> Best practices and conventions for Python numerical computing with NumPy, SciPy, and related libraries

## Array Creation Conventions

### Explicit dtype

Always specify dtype for clarity and reproducibility:

```python
# ✅ Explicit dtype
a = np.zeros((3, 4), dtype=np.float64)
b = np.array([1.0, 2.0, 3.0], dtype=np.float32)

# ⚠ Implicit dtype (platform-dependent default)
a = np.zeros((3, 4))  # float64 on most platforms, but not guaranteed
b = np.array([1, 2, 3])  # int64 on 64-bit, int32 on 32-bit
```

### Array vs Matrix

```python
# ✅ Use ndarray (standard)
A = np.array([[1, 2], [3, 4]])
result = A @ B  # Matrix multiply with @ operator

# ❌ Avoid np.matrix (deprecated)
A = np.matrix([[1, 2], [3, 4]])
```

---

## Testing Conventions

### numpy.testing Functions

| Function | Use Case | Example |
|----------|----------|---------|
| `assert_allclose` | Approximate equality (recommended) | `assert_allclose(actual, expected, rtol=1e-7)` |
| `assert_array_equal` | Exact equality (integers, bools) | `assert_array_equal(indices, [0, 1, 2])` |
| `assert_array_less` | Element-wise less than | `assert_array_less(errors, tolerance)` |
| `assert_equal` | Exact equality (scalars, objects) | `assert_equal(result.shape, (3, 4))` |

### pytest Integration

```python
import numpy as np
from numpy.testing import assert_allclose
import pytest

class TestMatrixOps:
    def test_inverse_identity(self):
        """A @ A_inv should equal identity matrix."""
        A = np.array([[1, 2], [3, 4]], dtype=np.float64)
        A_inv = np.linalg.inv(A)
        result = A @ A_inv
        expected = np.eye(2)
        assert_allclose(result, expected, atol=1e-14)

    def test_svd_reconstruction(self):
        """U @ diag(S) @ Vt should reconstruct original matrix."""
        A = np.random.randn(5, 3)
        U, S, Vt = np.linalg.svd(A, full_matrices=False)
        reconstructed = U @ np.diag(S) @ Vt
        assert_allclose(reconstructed, A, rtol=1e-12)

    @pytest.mark.parametrize("dtype", [np.float32, np.float64])
    def test_dtype_preservation(self, dtype):
        """Operations should preserve dtype."""
        a = np.ones(10, dtype=dtype)
        result = np.sum(a)
        assert result.dtype == dtype
```

### Hypothesis (Property-Based Testing)

```python
from hypothesis import given, settings
from hypothesis.extra.numpy import arrays
import hypothesis.strategies as st

@given(arrays(np.float64, shape=(10,), elements=st.floats(-1e6, 1e6, allow_nan=False)))
def test_sort_idempotent(arr):
    """Sorting twice should equal sorting once."""
    once = np.sort(arr)
    twice = np.sort(once)
    assert_array_equal(once, twice)

@given(arrays(np.float64, shape=(5, 5), elements=st.floats(-100, 100, allow_nan=False, allow_infinity=False)))
def test_transpose_involution(A):
    """Transposing twice should return original."""
    assert_array_equal(A.T.T, A)
```

---

## Error Handling Conventions

### NumPy Error States

```python
# Configure error handling
np.seterr(divide='raise', over='warn', under='ignore', invalid='raise')

# Context-based error handling
with np.errstate(divide='ignore'):
    result = a / b  # Division by zero won't raise/warn
```

### Recommended Settings for Development vs Production

```python
# Development: Strict — catch all issues
np.seterr(all='raise')

# Production: Balanced — warn on suspicious operations
np.seterr(divide='warn', over='warn', under='ignore', invalid='warn')

# Performance-critical: Silent — no overhead
np.seterr(all='ignore')
```

---

## Performance Conventions

### Prefer Vectorized Operations

```python
# ❌ Python loop
result = [math.sqrt(x) for x in data]

# ✅ Vectorized
result = np.sqrt(data)

# ❌ Element-wise conditional
for i in range(len(a)):
    if a[i] > threshold:
        result[i] = a[i]

# ✅ Vectorized conditional
result = np.where(a > threshold, a, 0)
```

### Prefer In-place Operations for Large Arrays

```python
# ❌ Creates temporary arrays
result = a * 2 + b * 3  # 2 temporaries

# ✅ In-place operations
result = np.empty_like(a)
np.multiply(a, 2, out=result)
np.add(result, b * 3, out=result)
# OR use np.einsum for complex operations
```

### Use Appropriate BLAS Operations

```python
# ❌ Manual matrix multiply
result = np.zeros((m, n))
for i in range(m):
    for j in range(n):
        for k in range(p):
            result[i, j] += a[i, k] * b[k, j]

# ✅ BLAS-accelerated
result = a @ b
# OR
result = np.dot(a, b)
# OR for batch operations
result = np.einsum('ijk,ikl->ijl', a, b)
```

---

## Code Style

### Import Conventions

```python
# Standard imports
import numpy as np
import scipy as sp
import scipy.linalg
import scipy.special
from numpy.testing import assert_allclose, assert_array_equal

# ❌ Avoid star imports
from numpy import *

# ❌ Avoid redundant aliases
import numpy as numpy
```

### Documentation for Numerical Functions

```python
def stable_softmax(x: np.ndarray, axis: int = -1) -> np.ndarray:
    """Compute softmax with numerical stability via max-subtraction.

    Parameters
    ----------
    x : np.ndarray
        Input logits. Any shape.
    axis : int
        Axis along which softmax is computed. Default: -1.

    Returns
    -------
    np.ndarray
        Softmax probabilities. Same shape as input, sums to 1 along axis.

    Notes
    -----
    Uses the identity softmax(x) = softmax(x - max(x)) to prevent overflow.
    Precision: float64 operations maintain ~15 decimal digits.

    Examples
    --------
    >>> stable_softmax(np.array([1.0, 2.0, 3.0]))
    array([0.09003057, 0.24472847, 0.66524096])
    """
    x_max = np.max(x, axis=axis, keepdims=True)
    exp_x = np.exp(x - x_max)
    return exp_x / np.sum(exp_x, axis=axis, keepdims=True)
```

---

## Type Annotation Conventions

```python
from typing import Union, Optional
import numpy as np
import numpy.typing as npt

# NumPy array type hints (Python 3.9+, NumPy 1.20+)
def normalize(
    x: npt.NDArray[np.float64],
    axis: int = -1,
) -> npt.NDArray[np.float64]:
    ...

# For generic numeric input
ArrayLike = Union[np.ndarray, list, float]
def process(data: npt.ArrayLike) -> np.ndarray:
    arr = np.asarray(data)
    ...
```
