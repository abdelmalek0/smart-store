import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ===========================================================================
// FFI TYPE DEFINITIONS
// ===========================================================================

// --- C Function Typedefs ---
typedef InitONNXFunc = Int32 Function();
typedef CreateSessionFunc = Int64 Function(Pointer<Utf8> modelPath);
typedef ReleaseSessionFunc = Void Function(Int64 sessionId);
typedef InferenceShutdownFunc = Void Function(); // Shutdown all GPU resources
typedef NativeForceExitFunc =
    Void Function(); // Force exit bypassing destructors
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
      Int64 sessionId,
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

// --- Video Capture C Function Typedefs ---
typedef VideoOpenFunc = Int64 Function(Pointer<Utf8> url);
typedef VideoReleaseFunc = Void Function(Int64 id);
typedef VideoGetFrameFunc =
    Int32 Function(
      Int64 id,
      Pointer<Pointer<Uint8>> outBuffer,
      Pointer<Int32> width,
      Pointer<Int32> height,
    );

typedef VideoGetFrameAndInferFunc =
    Int32 Function(
      Int64 videoId,
      Int64 sessionId,
      Pointer<Utf8> inputName,
      Pointer<Pointer<Utf8>> outputNames,
      Int32 numOutputs,
      Pointer<Pointer<Uint8>> outFrameBuffer,
      Pointer<Int32> outWidth,
      Pointer<Int32> outHeight,
      Pointer<Float> outInferenceTime,
    );

// --- Image Preprocessing C Function Typedefs ---
typedef PreprocessImageFunc =
    Int32 Function(
      Pointer<Uint8> inData,
      Int32 width,
      Int32 height,
      Pointer<Float> outData,
    );

// --- Dart Function Typedefs ---
typedef InitONNX = int Function();
typedef CreateSession = int Function(Pointer<Utf8> modelPath);
typedef ReleaseSession = void Function(int sessionId);
typedef InferenceShutdown = void Function(); // Shutdown all GPU resources
typedef NativeForceExit = void Function();
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
    int Function(
      int sessionId,
      Pointer<Pointer<Utf8>> outputNames,
      int numOutputs,
    );
typedef SessionGetOutput =
    int Function(
      int id,
      int index,
      Pointer<Pointer<Float>> data,
      Pointer<Pointer<Int64>> dims,
      Pointer<Int32> rank,
      Pointer<Int64> count,
    );

// Video Capture Dart Typedefs
typedef VideoOpen = int Function(Pointer<Utf8> url);
typedef VideoRelease = void Function(int id);
typedef VideoGetFrame =
    int Function(
      int id,
      Pointer<Pointer<Uint8>> outBuffer,
      Pointer<Int32> width,
      Pointer<Int32> height,
    );

typedef VideoGetFrameAndInfer =
    int Function(
      int videoId,
      int sessionId,
      Pointer<Utf8> inputName,
      Pointer<Pointer<Utf8>> outputNames,
      int numOutputs,
      Pointer<Pointer<Uint8>> outFrameBuffer,
      Pointer<Int32> outWidth,
      Pointer<Int32> outHeight,
      Pointer<Float> outInferenceTime,
    );

// Image Preprocessing Dart Typedef
typedef PreprocessImage =
    int Function(
      Pointer<Uint8> inData,
      int width,
      int height,
      Pointer<Float> outData,
    );
