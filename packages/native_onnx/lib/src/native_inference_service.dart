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
  late InferenceShutdown _inferenceShutdown;
  late NativeForceExit _nativeForceExit;
  late SessionClearInputs _clearInputs;
  late SessionAddInput _addInput;
  late SessionRun _run;
  late SessionGetOutput _getOutput;

  // Video
  late VideoOpen _videoOpen;
  late VideoRelease _videoRelease;
  late VideoGetFps _videoGetFps;
  late VideoGetFrame _videoGetFrame;
  late VideoGetFrameAndInfer _videoGetFrameAndInfer;
  late VideoInferenceOnly _videoInferenceOnly;
  late PreprocessImage _preprocessImage;
  late SessionGetLabels _getLabels;
  late TextureShowFrame _showFrame;

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
      } else if (Platform.isAndroid) {
        // On Android, load the library bundled in the APK
        _lib = DynamicLibrary.open('libnative_onnx_plugin.so');
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
        _inferenceShutdown = _lib!
            .lookupFunction<InferenceShutdownFunc, InferenceShutdown>(
              'Inference_Shutdown',
            );
        _nativeForceExit = _lib!
            .lookupFunction<NativeForceExitFunc, NativeForceExit>(
              'Native_ForceExit',
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
        _videoGetFps = _lib!.lookupFunction<VideoGetFpsFunc, VideoGetFps>(
          'Video_GetFPS',
        );
        _videoGetFrame = _lib!.lookupFunction<VideoGetFrameFunc, VideoGetFrame>(
          'Video_GetFrame',
        );
        _preprocessImage = _lib!
            .lookupFunction<PreprocessImageFunc, PreprocessImage>(
              'PreprocessImage',
            );
        _videoGetFrameAndInfer = _lib!
            .lookupFunction<VideoGetFrameAndInferFunc, VideoGetFrameAndInfer>(
              'Video_GetFrameAndInfer',
            );
        _videoInferenceOnly = _lib!
            .lookupFunction<VideoInferenceOnlyFunc, VideoInferenceOnly>(
              'Video_InferenceOnly',
            );
        _getLabels = _lib!
            .lookupFunction<SessionGetLabelsFunc, SessionGetLabels>(
              'Session_GetLabels',
            );
        _showFrame = _lib!
            .lookupFunction<TextureShowFrameFunc, TextureShowFrame>(
              'Texture_ShowFrame',
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

  /// Shutdown all GPU resources - MUST be called before app exit!
  /// This releases all ONNX sessions, video contexts, and CUDA resources
  /// in the correct order to prevent CUDA driver shutdown crashes.
  void shutdown() {
    if (!_isInitialized) return;
    _inferenceShutdown();
    _isInitialized = false;
    _initFuture = null;
  }

  /// Force immediate exit via C++ _Exit(0)
  /// This bypasses static destructors and prevents CUDA crashes
  void forceExit() {
    // We can force exit as long as the library is loaded,
    // even if we've already logically shutdown the inference engine
    debugPrint(
      "[Native] Force exit check: lib=${_lib != null ? 'loaded' : 'null'}",
    );
    if (_lib == null) return;
    try {
      _nativeForceExit();
    } catch (e) {
      debugPrint("[Native] Force exit failed: $e");
      exit(0); // Fallback to Dart exit
    }
  }

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
      for (int i = 0; i < tensor.shape.length; i++) {
        dimsPtr[i] = tensor.shape[i];
      }

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
    for (int i = 0; i < outputNames.length; i++) {
      calloc.free(outNamesPtr[i]);
    }
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
        for (int d = 0; d < rank; d++) {
          shape.add(dimsPtr[d]);
        }

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

  /// Get the native FPS of the video source.
  /// Returns > 0 for file sources (e.g. 25.0, 29.97).
  /// Returns 0.0 for live RTSP streams (no pacing needed — stream self-paces).
  double videoGetFps(int id) {
    if (!_isInitialized) return 0.0;
    return _videoGetFps(id);
  }

  /// Get a frame from a video stream
  /// Returns 0 on success, error code on failure
  int videoGetFrame(
    int id,
    Pointer<Pointer<Uint8>> bufferPtr,
    Pointer<Int32> w,
    Pointer<Int32> h,
    Pointer<Int64> timestamp,
  ) {
    return _videoGetFrame(id, bufferPtr, w, h, timestamp);
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

  /// Get frame AND infer
  /// Returns 0 on success
  int videoGetFrameAndInfer(
    int id,
    int sessionId,
    String inputName,
    List<String> outputNames,
    Pointer<Pointer<Uint8>> outBuffer,
    Pointer<Int32> width,
    Pointer<Int32> height,
    Pointer<Float> outInferenceTime,
    Pointer<Int64> outTimestamp,
  ) {
    if (!_isInitialized) return -1;

    final inputNamePtr = inputName.toNativeUtf8();
    final outNamesPtr = calloc<Pointer<Utf8>>(outputNames.length);
    for (int i = 0; i < outputNames.length; i++) {
      outNamesPtr[i] = outputNames[i].toNativeUtf8();
    }

    try {
      return _videoGetFrameAndInfer(
        id,
        sessionId,
        inputNamePtr,
        outNamesPtr,
        outputNames.length,
        outBuffer,
        width,
        height,
        outInferenceTime,
        outTimestamp,
      );
    } finally {
      calloc.free(inputNamePtr);
      for (int i = 0; i < outputNames.length; i++) {
        calloc.free(outNamesPtr[i]);
      }
      calloc.free(outNamesPtr);
    }
  }

  /// Run inference ONLY on the LAST captured frame (Zero-Copy 2.0)
  /// Returns 0 on success
  int videoInferenceOnly(
    int videoId,
    int sessionId,
    String inputName,
    List<String> outputNames,
    Pointer<Float> outInferenceTime,
  ) {
    if (!_isInitialized) return -1;

    final inputNamePtr = inputName.toNativeUtf8();
    final outNamesPtr = calloc<Pointer<Utf8>>(outputNames.length);
    for (int i = 0; i < outputNames.length; i++) {
      outNamesPtr[i] = outputNames[i].toNativeUtf8();
    }

    try {
      return _videoInferenceOnly(
        videoId,
        sessionId,
        inputNamePtr,
        outNamesPtr,
        outputNames.length,
        outInferenceTime,
      );
    } finally {
      calloc.free(inputNamePtr);
      for (int i = 0; i < outputNames.length; i++) {
        calloc.free(outNamesPtr[i]);
      }
      calloc.free(outNamesPtr);
    }
  }

  /// Retrieve outputs from a session (after a run)
  void getSessionOutputs(
    int id,
    List<String> outputNames,
    Map<String, List<dynamic>> outputs,
  ) {
    if (!_isInitialized) throw Exception("NativeService not initialized");

    for (int i = 0; i < outputNames.length; i++) {
      final dataPtrRef = calloc<Pointer<Float>>();
      final dimsPtrRef = calloc<Pointer<Int64>>();
      final rankRef = calloc<Int32>();
      final countRef = calloc<Int64>();

      try {
        if (_getOutput(id, i, dataPtrRef, dimsPtrRef, rankRef, countRef) == 0) {
          final count = countRef.value;
          final rank = rankRef.value;
          final dataPtr = dataPtrRef.value;
          final dimsPtr = dimsPtrRef.value;

          final dataList = Float32List.fromList(dataPtr.asTypedList(count));

          List<int> shape = [];
          for (int d = 0; d < rank; d++) {
            shape.add(dimsPtr[d]);
          }

          outputs[outputNames[i]] = [dataList, shape];
        }
      } finally {
        calloc.free(dataPtrRef);
        calloc.free(dimsPtrRef);
        calloc.free(rankRef);
        calloc.free(countRef);
      }
    }
  }

  /// Cache for parsed labels per session
  final Map<int, Map<int, String>> _labelsCache = {};

  /// Get class labels from ONNX model metadata
  /// Returns a map of classId -> class name
  /// Returns empty map if no labels found in model metadata
  Map<int, String> getLabels(int sessionId) {
    if (!_isInitialized) return {};

    // Check cache first
    if (_labelsCache.containsKey(sessionId)) {
      return _labelsCache[sessionId]!;
    }

    final labelsPtrRef = calloc<Pointer<Utf8>>();
    final lengthRef = calloc<Int32>();

    try {
      final result = _getLabels(sessionId, labelsPtrRef, lengthRef);
      if (result != 0 || labelsPtrRef.value == nullptr) {
        _labelsCache[sessionId] = {};
        return {};
      }

      final labelsStr = labelsPtrRef.value.toDartString();
      if (labelsStr.isEmpty) {
        _labelsCache[sessionId] = {};
        return {};
      }

      // Parse YOLO-style labels format: {0: 'person', 1: 'bicycle', ...}
      final labels = _parseYoloLabels(labelsStr);
      _labelsCache[sessionId] = labels;
      return labels;
    } finally {
      calloc.free(labelsPtrRef);
      calloc.free(lengthRef);
    }
  }

  /// Parse YOLO-style label format from ONNX metadata
  /// Handles format like: {0: 'person', 1: 'bicycle', 2: 'car', ...}
  Map<int, String> _parseYoloLabels(String labelsStr) {
    final Map<int, String> labels = {};

    // Remove outer braces if present
    var content = labelsStr.trim();
    if (content.startsWith('{')) content = content.substring(1);
    if (content.endsWith('}')) {
      content = content.substring(0, content.length - 1);
    }

    // Parse each key-value pair
    // Format: 0: 'person', 1: 'bicycle', ...
    final regex = RegExp(r'''(\d+)\s*:\s*['"]([^'"]+)['"]''');
    for (final match in regex.allMatches(content)) {
      final classId = int.tryParse(match.group(1)!);
      final className = match.group(2);
      if (classId != null && className != null) {
        labels[classId] = className;
      }
    }

    debugPrint('[Native] Parsed ${labels.length} labels from model metadata');
    return labels;
  }

  /// Show a specific frame (Strict Synchronization)
  /// Returns true if frame was shown, false if dropped/not found
  bool showFrame(int textureId, int timestamp) {
    if (!_isInitialized) return false;
    return _showFrame(textureId, timestamp) == 0;
  }
}
