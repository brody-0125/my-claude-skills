# Dart Tensor Conventions

> Best practices for numerical computing in Dart with dart_tensor_preprocessing and related libraries

## Core Types

### dart:typed_data

Dart's foundation for numerical arrays:

```dart
import 'dart:typed_data';

// Fixed-type numeric lists
Float32List data = Float32List(1000);       // 32-bit float array
Float64List precise = Float64List(1000);    // 64-bit float array
Int32List indices = Int32List(100);          // 32-bit integer array
Uint8List pixels = Uint8List(256 * 256);    // 8-bit unsigned (images)

// SIMD types
Float32x4List simd = data.buffer.asFloat32x4List();  // SIMD view
```

### TensorBuffer (dart_tensor_preprocessing)

```dart
import 'package:dart_tensor_preprocessing/dart_tensor_preprocessing.dart';

// Creation
final tensor = TensorBuffer.fromList([1.0, 2.0, 3.0, 4.0], shape: [2, 2]);
final zeros = TensorBuffer.zeros(shape: [3, 224, 224]);
final fromImage = TensorBuffer.fromUint8List(imageBytes, shape: [1, 224, 224, 3]);

// Properties
tensor.shape;    // [2, 2]
tensor.dtype;    // Float32
tensor.strides;  // Stride information for memory layout
```

---

## Pipeline Conventions

### Pre-configured Pipelines

```dart
// ✅ Use preset pipelines for standard models
final resnetPipeline = PreprocessingPipeline.resnet();
final yoloPipeline = PreprocessingPipeline.yolo();
final clipPipeline = PreprocessingPipeline.clip();

final result = resnetPipeline.process(inputTensor);
```

### Custom Pipelines

```dart
// ✅ Declarative pipeline definition
final pipeline = PreprocessingPipeline([
  Resize(targetSize: Size(224, 224)),
  Normalize(mean: [0.485, 0.456, 0.406], std: [0.229, 0.224, 0.225]),
  Permute(order: [2, 0, 1]),  // HWC → CHW
  CastDtype(dtype: TensorDtype.float32),
]);

// ❌ Avoid imperative step-by-step transformation
var tensor = inputTensor;
tensor = resize(tensor, 224, 224);
tensor = normalize(tensor, mean, std);
tensor = permute(tensor, [2, 0, 1]);
```

---

## SIMD Best Practices

### Float32x4 Operations

```dart
// ✅ SIMD-accelerated element-wise operation
void multiplyScalar(Float32List data, double scalar) {
  final scalarX4 = Float32x4.splat(scalar.toFloat());
  final simdView = data.buffer.asFloat32x4List();

  for (var i = 0; i < simdView.length; i++) {
    simdView[i] = simdView[i] * scalarX4;
  }

  // Handle remaining elements
  final remainder = data.length % 4;
  final start = data.length - remainder;
  for (var i = start; i < data.length; i++) {
    data[i] *= scalar;
  }
}
```

### Alignment Considerations

```dart
// ✅ Allocate aligned buffer for SIMD
final buffer = Float32List(alignToFour(length));

// ✅ Helper to align length to SIMD width
int alignToFour(int length) => (length + 3) & ~3;

// ⚠ Sublist views may break SIMD alignment
final sub = Float32List.sublistView(buffer, 1);  // Offset by 1 → misaligned!
```

---

## Zero-Copy Operations

### Views vs Copies

```dart
// ✅ Zero-copy reshape (O(1))
final reshaped = tensor.reshape([4, 1]);  // Same underlying buffer

// ✅ Zero-copy transpose (O(1))
final transposed = tensor.transpose();  // Stride manipulation only

// ⚠ Some operations require copy
final sliced = tensor.slice([0, 0], [1, 2]);  // May copy depending on implementation
```

### Buffer Pool

```dart
// ✅ Use buffer pool for repeated allocations
final pool = TensorBufferPool(maxSize: 10);
final buffer = pool.acquire(shape: [1, 3, 224, 224]);
try {
  // Use buffer...
} finally {
  pool.release(buffer);
}
```

---

## Isolate Safety

### Cross-Isolate Data Transfer

```dart
// ✅ TransferableTypedData for zero-copy cross-isolate transfer
final transferable = TransferableTypedData.fromList([tensor.data]);
final receivePort = ReceivePort();
await Isolate.spawn(processInIsolate, transferable);

// ❌ Sending raw Float32List copies all data
isolate.send(tensor.data);  // Full copy!
```

### Compute Isolation Pattern

```dart
// ✅ Heavy computation in isolate to avoid UI jank
Future<TensorBuffer> processAsync(TensorBuffer input) async {
  return await Isolate.run(() {
    // Preprocessing runs in background isolate
    final pipeline = PreprocessingPipeline.resnet();
    return pipeline.process(input);
  });
}
```

---

## Testing Conventions

### Numeric Assertions

```dart
import 'package:test/test.dart';

void main() {
  test('normalization produces unit range', () {
    final input = TensorBuffer.fromList(
      [0.0, 127.5, 255.0],
      shape: [3],
    );
    final normalized = normalize(input);

    // ✅ Tolerance-based comparison
    for (var i = 0; i < normalized.length; i++) {
      expect(normalized[i], closeTo(expectedValues[i], 1e-6));
    }
  });

  test('reshape preserves element count', () {
    final tensor = TensorBuffer.zeros(shape: [2, 3, 4]);
    final reshaped = tensor.reshape([6, 4]);

    expect(reshaped.shape, equals([6, 4]));
    // Total elements unchanged
    expect(
      reshaped.shape.reduce((a, b) => a * b),
      equals(tensor.shape.reduce((a, b) => a * b)),
    );
  });

  test('SIMD and scalar paths produce same result', () {
    final data = Float32List.fromList(
      List.generate(100, (i) => i.toDouble()),
    );

    final simdResult = multiplySIMD(data, 2.5);
    final scalarResult = multiplyScalar(data, 2.5);

    for (var i = 0; i < data.length; i++) {
      expect(simdResult[i], closeTo(scalarResult[i], 1e-6),
        reason: 'Mismatch at index $i');
    }
  });
}
```

### Edge Case Testing

```dart
test('handles empty tensor', () {
  final empty = TensorBuffer.zeros(shape: [0]);
  expect(empty.shape, equals([0]));
});

test('handles single element', () {
  final single = TensorBuffer.fromList([42.0], shape: [1]);
  final normalized = normalize(single);
  expect(normalized[0], isNotNaN);
});

test('handles extreme values', () {
  final extreme = TensorBuffer.fromList(
    [double.maxFinite, double.minPositive, 0.0, -0.0],
    shape: [4],
  );
  final result = process(extreme);
  for (var i = 0; i < result.length; i++) {
    expect(result[i], isNot(isNaN), reason: 'NaN at index $i');
    expect(result[i].isFinite, isTrue, reason: 'Inf at index $i');
  }
});
```

---

## Code Style

### Import Conventions

```dart
// ✅ Standard imports
import 'dart:typed_data';
import 'package:dart_tensor_preprocessing/dart_tensor_preprocessing.dart';
import 'package:ml_linalg/ml_linalg.dart';

// ✅ Test imports
import 'package:test/test.dart';
```

### Documentation

```dart
/// Normalizes tensor values to [0, 1] range using min-max scaling.
///
/// For each element: `(x - min) / (max - min)`
///
/// Handles edge case where max == min by returning zeros.
///
/// **Precision**: Maintains Float32 precision (~7 decimal digits).
///
/// [input] must have at least one element.
/// Returns a new [TensorBuffer] with the same shape.
TensorBuffer minMaxNormalize(TensorBuffer input) {
  // ...
}
```

---

## ONNX Runtime Integration

```dart
// ✅ Preprocessing for ONNX model inference
final session = OrtSession.fromBuffer(modelBytes);
final preprocessed = pipeline.process(inputTensor);

// Ensure correct input format
final ortValue = OrtValue.fromFloat32List(
  preprocessed.data as Float32List,
  preprocessed.shape,
);

final outputs = session.run({'input': ortValue});
```

### dtype Compatibility

| ONNX Type | Dart Type | TensorBuffer dtype |
|-----------|-----------|-------------------|
| FLOAT | Float32List | TensorDtype.float32 |
| INT64 | Int64List | TensorDtype.int64 |
| UINT8 | Uint8List | TensorDtype.uint8 |
| DOUBLE | Float64List | TensorDtype.float64 |
