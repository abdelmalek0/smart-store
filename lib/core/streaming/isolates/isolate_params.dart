import 'dart:isolate';
import 'dart:ui';

/// Parameters for initializing the video capture isolate
class IsolateInitParams {
  final SendPort sendPort;
  final String videoUrl;
  final RootIsolateToken rootIsolateToken;
  final String? modelPath;

  IsolateInitParams(
    this.sendPort,
    this.videoUrl,
    this.rootIsolateToken, {
    this.modelPath,
  });
}
