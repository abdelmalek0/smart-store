import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef OpenVideoNative = Int64 Function(Pointer<Utf8> url);
typedef OpenVideo = int Function(Pointer<Utf8> url);

typedef GetFrameNative =
    Int32 Function(
      Int64 ctx,
      Pointer<Int32> width,
      Pointer<Int32> height,
      Pointer<Uint8> data,
    );
typedef GetFrame =
    int Function(
      int ctx,
      Pointer<Int32> width,
      Pointer<Int32> height,
      Pointer<Uint8> data,
    );

typedef CloseVideoNative = Void Function(Int64 ctx);
typedef CloseVideo = void Function(int ctx);

class VLCVideoService {
  static DynamicLibrary? _lib;

  static OpenVideo? _openVideo;
  static GetFrame? _getFrame;
  static CloseVideo? _closeVideo;

  static void init() {
    if (_lib != null) return;

    _lib = DynamicLibrary.open('libnative_onnx_plugin.so');
    _openVideo = _lib!.lookupFunction<OpenVideoNative, OpenVideo>(
      'Java_com_example_native_1onnx_VLCVideo_openVideo',
    );
    _getFrame = _lib!.lookupFunction<GetFrameNative, GetFrame>(
      'Java_com_example_native_1onnx_VLCVideo_getFrame',
    );
    _closeVideo = _lib!.lookupFunction<CloseVideoNative, CloseVideo>(
      'Java_com_example_native_1onnx_VLCVideo_closeVideo',
    );
  }

  static int openVideo(String url) {
    init();
    final urlPtr = url.toNativeUtf8();
    final ctx = _openVideo!(urlPtr);
    calloc.free(urlPtr);
    return ctx;
  }

  static Uint8List? getFrame(
    int ctx,
    Pointer<Int32> width,
    Pointer<Int32> height,
  ) {
    final data = calloc<Uint8>(1920 * 1080 * 4);
    final result = _getFrame!(ctx, width, height, data);

    if (result == 0) {
      final w = width.value;
      final h = height.value;
      final list = Uint8List.fromList(data.asTypedList(w * h * 4));
      calloc.free(data);
      return list;
    }

    calloc.free(data);
    return null;
  }

  static void closeVideo(int ctx) {
    _closeVideo!(ctx);
  }
}
