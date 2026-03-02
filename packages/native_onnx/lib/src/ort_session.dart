import 'dart:io';
import 'package:native_onnx/src/native_inference_service.dart';
import 'package:native_onnx/src/ort_tensor.dart';

/// ONNX Runtime run options
class NativeOrtRunOptions {
  /// Release resources (no-op for now)
  void release() {}
}

/// ONNX Runtime session
class NativeOrtSession {
  final int _id;
  int get sessionId => _id;
  final NativeInferenceService _service = NativeInferenceService();
  bool _released = false;

  NativeOrtSession._(this._id);

  /// Create a session from a model file
  static Future<NativeOrtSession> fromFile(File file) async {
    final service = NativeInferenceService();
    await service.init();
    final id = service.createSession(file.path);
    if (id == 0) throw Exception("Failed to create session for ${file.path}");
    return NativeOrtSession._(id);
  }

  /// Run inference on the session
  List<List<dynamic>> run(
    NativeOrtRunOptions options,
    Map<String, NativeOrtValueTensor> inputs,
  ) {
    if (_released) throw Exception("Session released");

    // Default output names mapping
    List<String> outNames = [];
    if (inputs.containsKey('images')) {
      outNames = ["output0"]; // Standard YOLOv8 name
    } else if (inputs.containsKey('input')) {
      // VAD
      outNames = ["output", "hn", "cn"];
    } else {
      outNames = ["output0"];
    }

    Map<String, List<dynamic>> results = {};
    _service.runSession(_id, inputs, outNames, results);

    List<List<dynamic>> returnList = [];
    for (var name in outNames) {
      if (results.containsKey(name)) {
        // Return [dataList, shape] instead of just [dataList]
        returnList.add(results[name]!);
      }
    }
    return returnList;
  }

  /// Release the session
  void release() {
    if (!_released) {
      _service.releaseSession(_id);
      _released = true;
    }
  }
}
