import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_onnx_platform_interface.dart';

/// An implementation of [NativeOnnxPlatform] that uses method channels.
class MethodChannelNativeOnnx extends NativeOnnxPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('native_onnx');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
