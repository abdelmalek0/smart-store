import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Tensor value wrapper for ONNX Runtime
class NativeOrtValueTensor {
  final Pointer<Float> dataPtr;
  final List<int> shape;
  final bool _managed;

  NativeOrtValueTensor._(this.dataPtr, this.shape, this._managed);

  /// Create a tensor from a Float32List
  static NativeOrtValueTensor createTensorWithDataList(
    Float32List data,
    List<int> shape,
  ) {
    final ptr = calloc<Float>(data.length);
    final list = ptr.asTypedList(data.length);
    list.setAll(0, data);
    return NativeOrtValueTensor._(ptr, shape, true);
  }

  /// Create a single-value tensor
  static NativeOrtValueTensor createTensorWithData(num value) {
    final ptr = calloc<Float>(1);
    ptr[0] = value.toDouble();
    return NativeOrtValueTensor._(ptr, [1], true);
  }

  /// Create a tensor from an existing pointer (unmanaged)
  static NativeOrtValueTensor createTensorFromPointer(
    Pointer<Float> ptr,
    List<int> shape,
  ) {
    return NativeOrtValueTensor._(ptr, shape, false);
  }

  /// Release managed memory
  void release() {
    if (_managed) calloc.free(dataPtr);
  }
}
