import 'package:flutter_test/flutter_test.dart';
import 'package:native_onnx/native_onnx.dart';

import 'package:native_onnx/native_onnx_platform_interface.dart';
import 'package:native_onnx/native_onnx_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNativeOnnxPlatform
    with MockPlatformInterfaceMixin
    implements NativeOnnxPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NativeOnnxPlatform initialPlatform = NativeOnnxPlatform.instance;

  test('$MethodChannelNativeOnnx is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNativeOnnx>());
  });

  test('init', () async {
    NativeInferenceService nativeOnnxPlugin = NativeInferenceService();
    // Verify it doesn't throw
    await nativeOnnxPlugin.init();
  });
}
