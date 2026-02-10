import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// Native function signatures
typedef OpenVideoNative = Int64 Function(Pointer<Utf8> url);
typedef OpenVideo = int Function(Pointer<Utf8> url);

typedef GetFrameNative =
    Int32 Function(
      Int64 ctx,
      Pointer<Pointer<Uint8>> bufferOut,
      Pointer<Int32> widthOut,
      Pointer<Int32> heightOut,
    );
typedef GetFrame =
    int Function(
      int ctx,
      Pointer<Pointer<Uint8>> bufferOut,
      Pointer<Int32> widthOut,
      Pointer<Int32> heightOut,
    );

typedef CloseVideoNative = Void Function(Int64 ctx);
typedef CloseVideo = void Function(int ctx);

class LibVLCBridge {
  static DynamicLibrary? _lib;
  static bool _initialized = false;

  static OpenVideo? _openVideo;
  static GetFrame? _getFrame;
  static CloseVideo? _closeVideo;

  static void init() {
    if (_initialized) return;

    try {
      _lib = DynamicLibrary.open('libffmpeg_video.so');

      _openVideo = _lib!.lookupFunction<OpenVideoNative, OpenVideo>(
        'Java_com_example_native_1onnx_VLCVideo_openVideo',
      );
      _getFrame = _lib!.lookupFunction<GetFrameNative, GetFrame>(
        'Java_com_example_native_1onnx_VLCVideo_getFrame',
      );
      _closeVideo = _lib!.lookupFunction<CloseVideoNative, CloseVideo>(
        'Java_com_example_native_1onnx_VLCVideo_closeVideo',
      );

      _initialized = true;
      debugPrint('✓ LibVLC bridge initialized');
    } catch (e) {
      debugPrint('❌ LibVLC init failed: $e');
      throw Exception('Failed to initialize LibVLC: $e');
    }
  }

  static int openVideo(String url) {
    init();
    final urlPtr = url.toNativeUtf8();
    try {
      final ctx = _openVideo!(urlPtr);
      return ctx;
    } finally {
      calloc.free(urlPtr);
    }
  }

  static VideoFrame? getFrame(int ctx) {
    if (_getFrame == null) return null;

    final bufferPtr = calloc<Pointer<Uint8>>();
    final widthPtr = calloc<Int32>();
    final heightPtr = calloc<Int32>();

    try {
      final result = _getFrame!(ctx, bufferPtr, widthPtr, heightPtr);

      if (result == 0) {
        final w = widthPtr.value;
        final h = heightPtr.value;
        final dataPtr = bufferPtr.value;

        if (w > 0 && h > 0 && dataPtr != nullptr) {
          final length = w * h * 4; // RGBA
          final data = Uint8List.fromList(dataPtr.asTypedList(length));
          return VideoFrame(data, w, h);
        }
      }
      return null;
    } finally {
      calloc.free(bufferPtr);
      calloc.free(widthPtr);
      calloc.free(heightPtr);
    }
  }

  static void closeVideo(int ctx) {
    if (_closeVideo != null) {
      _closeVideo!(ctx);
    }
  }
}

class VideoFrame {
  final Uint8List data;
  final int width;
  final int height;

  VideoFrame(this.data, this.width, this.height);
}
