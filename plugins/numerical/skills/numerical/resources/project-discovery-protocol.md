# Project Discovery Protocol

> Phase 0: Numeric project profile auto-detection procedure

## Required Reads

None — this is the first phase.

---

## Step 1: Language Detection

```
1. Check for Python indicators:
   - pyproject.toml, setup.py, setup.cfg, requirements.txt, Pipfile, poetry.lock
   - *.py files in src/ or project root

2. Check for Dart indicators:
   - pubspec.yaml, analysis_options.yaml
   - *.dart files in lib/ or project root

3. Determine language:
   - Python files only → language=python
   - Dart files only → language=dart
   - Both present → language=mixed
```

## Step 2: Numeric Library Detection

### Python Libraries

```
1. Parse pyproject.toml [project.dependencies] or requirements.txt:
   - numpy → ndarray operations, broadcasting, linear algebra
   - scipy → scientific computing, sparse matrices, optimization
   - cupy → GPU-accelerated NumPy-compatible arrays
   - torch/pytorch → tensor operations, autograd, GPU
   - tensorflow → tensor operations, GPU/TPU
   - jax → composable transformations, XLA compilation
   - numba → JIT compilation, CUDA kernels
   - dask → parallel/distributed arrays
   - xarray → labeled multi-dimensional arrays
   - pandas → DataFrame (numeric column operations)

2. Detect C/Fortran extensions:
   - setup.py with numpy.distutils or Extension modules
   - Cython (.pyx) files
   - f2py (.f90, .f) files
   - cffi/ctypes bindings

3. Record detected libraries in profile:
   numeric-libs: [numpy, scipy, cupy, ...]
   has-native-extensions: true/false
   extension-languages: [c, cpp, fortran, cython]
```

### Dart Libraries

```
1. Parse pubspec.yaml dependencies:
   - dart_tensor_preprocessing → tensor operations, SIMD
   - ml_linalg → linear algebra
   - ml_dataframe → data manipulation
   - tflite_flutter → TFLite inference
   - onnxruntime → ONNX inference

2. Check for FFI bindings:
   - dart:ffi imports
   - native library loading (.so, .dylib, .dll)

3. Record detected libraries in profile:
   numeric-libs: [dart_tensor_preprocessing, ml_linalg, ...]
   has-ffi: true/false
```

## Step 3: GPU Capability Detection

```
1. Python GPU detection:
   - cupy in dependencies → CUDA GPU
   - torch.cuda references in code → PyTorch CUDA
   - tensorflow-gpu or tf.device('/GPU') → TensorFlow GPU
   - jax[cuda] or jax.devices() → JAX GPU
   - numba.cuda → Numba CUDA kernels

2. Dart GPU detection:
   - gpu_compute or similar packages
   - Platform-specific GPU bindings via FFI

3. Record GPU profile:
   gpu-support: true/false
   gpu-framework: [cuda, opencl, metal, vulkan]
   gpu-libs: [cupy, torch.cuda, ...]
```

## Step 4: Test Framework Detection

```
1. Python test detection:
   - pytest (pytest.ini, conftest.py, pyproject.toml [tool.pytest])
   - unittest (test_*.py with unittest.TestCase)
   - hypothesis (hypothesis strategies)
   - numpy.testing assertions in test files

2. Dart test detection:
   - dart test (test/ directory, pubspec.yaml dev_dependencies)
   - flutter_test

3. Record test profile:
   test-framework: [pytest, hypothesis, ...]
   has-numeric-assertions: true/false (numpy.testing, assert_allclose)
   has-property-tests: true/false (hypothesis)
```

## Step 5: Analysis Tool Detection

```
1. Python tools:
   - ruff (ruff.toml, pyproject.toml [tool.ruff])
   - flake8 (.flake8, setup.cfg)
   - mypy (mypy.ini, pyproject.toml [tool.mypy])
   - pylint (.pylintrc)
   - black/isort (formatting)
   - bandit (security)

2. Dart tools:
   - dart analyze (analysis_options.yaml)
   - dart format
   - custom_lint

3. Record in .numerical/analysis-tools.txt:
   One tool per line. User can edit to enable/disable.
```

## Step 6: Numeric Profile Generation

Generate and cache the profile:

```
Cache location: ~/.claude/cache/numerical-{hash}-{project-name}-profile.md

Profile content:
## Numeric Profile

- **project-dir**: {absolute path}
- **language**: python | dart | mixed
- **numeric-libs**: [list]
- **has-native-extensions**: true/false
- **extension-languages**: [c, cpp, fortran, cython]
- **gpu-support**: true/false
- **gpu-framework**: [cuda, opencl, ...]
- **test-framework**: [pytest, hypothesis, ...]
- **has-numeric-assertions**: true/false
- **has-property-tests**: true/false
- **primary-dtype**: float64 | float32 | ...
- **analysis-tools**: [ruff, mypy, ...]
```

## Step 7: Hooks Installation

```
1. Check if .claude/settings.json exists and has hooks
2. If no hooks: Install via scripts/setup-hooks.sh --auto
3. If hooks exist: Skip (avoid duplicate installation)
```

---

## Phase Handoff

**Entry Condition**: Session start or explicit `/numerical` invocation

**Exit Condition**: Numeric profile loaded and cached

**Next Phase**: Phase 1 (Analyze)

**Failure Fallback**: If no numeric libraries detected, warn user and proceed with generic floating-point analysis mode.
