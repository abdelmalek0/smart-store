// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:native_onnx/native_onnx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('init test', (WidgetTester tester) async {
    final NativeInferenceService plugin = NativeInferenceService();
    await plugin.init();
    // Since we can't easily check internal state without accessors,
    // we just verify it doesn't throw.
  });
}
