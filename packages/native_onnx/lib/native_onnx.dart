import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

// --- FFI Typedefs ---
typedef InitONNXFunc = Int32 Function();
typedef CreateSessionFunc = Int64 Function(Pointer<Utf8> path);
typedef ReleaseSessionFunc = Void Function(Int64 id);
typedef SessionClearInputsFunc = Void Function(Int64 id);
typedef SessionAddInputFunc =
    Void Function(
      Int64 id,
      Pointer<Utf8> name,
      Pointer<Float> data,
      Pointer<Int64> dims,
      Int32 rank,
    );
typedef SessionRunFunc =
    Int32 Function(
      Int64 id,
      Pointer<Pointer<Utf8>> outputNames,
      Int32 numOutputs,
    );
typedef SessionGetOutputFunc =
    Int32 Function(
      Int64 id,
      Int32 index,
      Pointer<Pointer<Float>> data,
      Pointer<Pointer<Int64>> dims,
      Pointer<Int32> rank,
      Pointer<Int64> count,
    );

// Dart definitions
typedef InitONNX = int Function();
typedef CreateSession = int Function(Pointer<Utf8> path);
typedef ReleaseSession = void Function(int id);
typedef SessionClearInputs = void Function(int id);
typedef SessionAddInput =
    void Function(
      int id,
      Pointer<Utf8> name,
      Pointer<Float> data,
      Pointer<Int64> dims,
      int rank,
    );
typedef SessionRun =
    int Function(int id, Pointer<Pointer<Utf8>> outputNames, int numOutputs);
typedef SessionGetOutput =
    int Function(
      int id,
      int index,
      Pointer<Pointer<Float>> data,
      Pointer<Pointer<Int64>> dims,
      Pointer<Int32> rank,
      Pointer<Int64> count,
    );

class NativeInferenceService {
  static final NativeInferenceService _instance =
      NativeInferenceService._internal();
  factory NativeInferenceService() => _instance;
  NativeInferenceService._internal();

  DynamicLibrary? _lib;
  late InitONNX _initONNX;
  late CreateSession _createSession;
  late ReleaseSession _releaseSession;
  late SessionClearInputs _clearInputs;
  late SessionAddInput _addInput;
  late SessionRun _run;
  late SessionGetOutput _getOutput;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      if (Platform.isLinux) {
        try {
          _lib = DynamicLibrary.open('libnative_onnx_plugin.so');
        } catch (e) {
          final libraryPath = p.join(
            p.dirname(Platform.resolvedExecutable),
            'lib',
            'libnative_onnx_plugin.so',
          );
          _lib = DynamicLibrary.open(libraryPath);
        }
      }

      _initONNX = _lib!.lookupFunction<InitONNXFunc, InitONNX>('InitONNX');
      _createSession = _lib!.lookupFunction<CreateSessionFunc, CreateSession>(
        'CreateSession',
      );
      _releaseSession = _lib!
          .lookupFunction<ReleaseSessionFunc, ReleaseSession>('ReleaseSession');
      _clearInputs = _lib!
          .lookupFunction<SessionClearInputsFunc, SessionClearInputs>(
            'Session_ClearInputs',
          );
      _addInput = _lib!.lookupFunction<SessionAddInputFunc, SessionAddInput>(
        'Session_AddInput',
      );
      _run = _lib!.lookupFunction<SessionRunFunc, SessionRun>('Session_Run');
      _getOutput = _lib!.lookupFunction<SessionGetOutputFunc, SessionGetOutput>(
        'Session_GetOutput',
      );

      _initONNX();
      _isInitialized = true;
      debugPrint("[Native] Service Initialized");
    } catch (e) {
      debugPrint("[Native] Init Failed: $e");
    }
  }

  // --- Wrapper functionality mimics package API ---

  int createSession(String path) {
    if (!_isInitialized) throw Exception("NativeService not initialized");
    final ptr = path.toNativeUtf8();
    try {
      return _createSession(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  void releaseSession(int id) => _releaseSession(id);

  void runSession(
    int id,
    Map<String, NativeOrtValueTensor> inputs,
    List<String> outputNames,
    Map<String, List<dynamic>> outputs,
  ) {
    _clearInputs(id);

    // Add Inputs
    inputs.forEach((name, tensor) {
      final namePtr = name.toNativeUtf8();
      final dimsPtr = calloc<Int64>(tensor.shape.length);
      for (int i = 0; i < tensor.shape.length; i++)
        dimsPtr[i] = tensor.shape[i];

      _addInput(id, namePtr, tensor.dataPtr, dimsPtr, tensor.shape.length);

      calloc.free(namePtr);
      calloc.free(dimsPtr);
    });

    // Prepare output names
    final outNamesPtr = calloc<Pointer<Utf8>>(outputNames.length);
    for (int i = 0; i < outputNames.length; i++) {
      outNamesPtr[i] = outputNames[i].toNativeUtf8();
    }

    // Run
    final result = _run(id, outNamesPtr, outputNames.length);

    // Cleanup names
    for (int i = 0; i < outputNames.length; i++) calloc.free(outNamesPtr[i]);
    calloc.free(outNamesPtr);

    if (result != 0) throw Exception("Inference Failed with code $result");

    // Retrieve Outputs
    for (int i = 0; i < outputNames.length; i++) {
      final dataPtrRef = calloc<Pointer<Float>>();
      final dimsPtrRef = calloc<Pointer<Int64>>();
      final rankRef = calloc<Int32>();
      final countRef = calloc<Int64>();

      if (_getOutput(id, i, dataPtrRef, dimsPtrRef, rankRef, countRef) == 0) {
        final count = countRef.value;
        final rank = rankRef.value;
        final dataPtr = dataPtrRef.value;
        final dimsPtr = dimsPtrRef.value;

        // Reconstruct logic
        final dataList = Float32List.fromList(dataPtr.asTypedList(count));

        // Shape
        List<int> shape = [];
        for (int d = 0; d < rank; d++) shape.add(dimsPtr[d]);

        outputs[outputNames[i]] = [dataList, shape];
      } else {
        debugPrint("Failed to get output $i");
      }

      calloc.free(dataPtrRef);
      calloc.free(dimsPtrRef);
      calloc.free(rankRef);
      calloc.free(countRef);
    }
  }
}

class NativeOrtValueTensor {
  final Pointer<Float> dataPtr;
  final List<int> shape;
  final bool _managed;

  NativeOrtValueTensor._(this.dataPtr, this.shape, this._managed);

  static NativeOrtValueTensor createTensorWithDataList(
    Float32List data,
    List<int> shape,
  ) {
    final ptr = calloc<Float>(data.length);
    final list = ptr.asTypedList(data.length);
    list.setAll(0, data);
    return NativeOrtValueTensor._(ptr, shape, true);
  }

  static NativeOrtValueTensor createTensorWithData(num value) {
    final ptr = calloc<Float>(1);
    ptr[0] = value.toDouble();
    return NativeOrtValueTensor._(ptr, [1], true);
  }

  void release() {
    if (_managed) calloc.free(dataPtr);
  }
}

class NativeOrtRunOptions {
  void release() {}
}

class NativeOrtSession {
  late int _id;
  final NativeInferenceService _service = NativeInferenceService();
  bool _released = false;

  NativeOrtSession._(this._id);

  static Future<NativeOrtSession> fromFile(File file) async {
    final service = NativeInferenceService();
    await service.init();
    final id = service.createSession(file.path);
    if (id == 0) throw Exception("Failed to create session for ${file.path}");
    return NativeOrtSession._(id);
  }

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
        returnList.add([results[name]![0]]);
      }
    }
    return returnList;
  }

  void release() {
    if (!_released) {
      _service.releaseSession(_id);
      _released = true;
    }
  }
}
