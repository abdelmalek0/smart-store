import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/src/ffi_types.dart';
import 'package:path/path.dart' as p;

/// Native inference service that wraps the C++ ONNX Runtime bridge
/// 
/// Singleton service that manages:
/// - ONNX Runtime initialization
/// - Session creation and management
/// - Inference execution
/// - Video capture operations
/// - Image preprocessing
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

  // Video
  late VideoOpen _videoOpen;
  late VideoRelease _videoRelease;
  late VideoGetFrame _videoGetFrame;
  late PreprocessImage _preprocessImage;

  bool _isInitialized = false;
  Future<void>? _initFuture;

  /// Initialize the native inference service
  Future<void> init() async {
    if (_isInitialized) return;
    if (_initFuture != null) return _initFuture;

    _initFuture = _doInit();
    return _initFuture;
  }

  /// Internal initialization implementation
  Future<void> _doInit() async {
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

      if (_lib != null) {
        _initONNX = _lib!.lookupFunction<InitONNXFunc, InitONNX>('InitONNX');
        _createSession = _lib!.lookupFunction<CreateSessionFunc, CreateSession>(
          'CreateSession',
        );
        _releaseSession = _lib!
            .lookupFunction<ReleaseSessionFunc, ReleaseSession>(
              'ReleaseSession',
            );
        _clearInputs = _lib!
            .lookupFunction<SessionClearInputsFunc, SessionClearInputs>(
              'Session_ClearInputs',
            );
        _addInput = _lib!.lookupFunction<SessionAddInputFunc, SessionAddInput>(
          'Session_AddInput',
        );
        _run = _lib!.lookupFunction<SessionRunFunc, SessionRun>('Session_Run');
        _getOutput = _lib!
            .lookupFunction<SessionGetOutputFunc, SessionGetOutput>(
              'Session_GetOutput',
            );

        _videoOpen = _lib!.lookupFunction<VideoOpenFunc, VideoOpen>(
          'Video_Open',
        );
        _videoRelease = _lib!.lookupFunction<VideoReleaseFunc, VideoRelease>(
          'Video_Release',
        );
        _videoGetFrame = _lib!.lookupFunction<VideoGetFrameFunc, VideoGetFrame>(
          'Video_GetFrame',
        );
        _preprocessImage = _lib!
            .lookupFunction<PreprocessImageFunc, PreprocessImage>(
              'PreprocessImage',
            );

        _initONNX();
        _isInitialized = true;
      }
    } catch (e) {
      debugPrint("[Native] Init Failed: $e");
      _isInitialized = false;
      _initFuture = null; // Allow retry
    }
  }

  /// Create an ONNX session from a model file path
  int createSession(String path) {
    if (!_isInitialized) throw Exception("NativeService not initialized");
    final ptr = path.toNativeUtf8();
    try {
      return _createSession(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Release an ONNX session
  void releaseSession(int id) => _releaseSession(id);

  /// Run inference on a session
  void runSession(
    int id,
    Map<String, dynamic> inputs,
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

  /// Open a video stream from URL
  int videoOpen(String url) {
    if (!_isInitialized) throw Exception("NativeService not initialized");
    final ptr = url.toNativeUtf8();
    try {
      return _videoOpen(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Release a video stream
  void videoRelease(int id) => _videoRelease(id);

  /// Get a frame from a video stream
  /// Returns 0 on success, error code on failure
  int videoGetFrame(
    int id,
    Pointer<Pointer<Uint8>> bufferPtr,
    Pointer<Int32> w,
    Pointer<Int32> h,
  ) {
    return _videoGetFrame(id, bufferPtr, w, h);
  }

  /// Preprocess an image for inference
  int preprocessImage(
    Pointer<Uint8> inData,
    int width,
    int height,
    Pointer<Float> outData,
  ) {
    return _preprocessImage(inData, width, height, outData);
  }
}
