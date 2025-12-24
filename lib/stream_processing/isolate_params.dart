import 'dart:isolate';

/// Parameters for initializing the video capture isolate
class IsolateInitParams {
  final String videoUrl;
  final SendPort sendPort;

  IsolateInitParams(this.videoUrl, this.sendPort);
}
