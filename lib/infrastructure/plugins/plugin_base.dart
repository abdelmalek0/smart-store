import 'dart:async';
import 'dart:isolate';

import 'package:smart_store_linux/domain/entities/raw_frame.dart';
import 'package:smart_store_linux/application/events/base/event_severity.dart';

/// Base class for all SmartStore Plugins
/// Plugins run in their own Isolate.
abstract class SmartStorePlugin {
  SendPort? _hostPort;
  String? _streamId;
  String? _pluginId;

  String get streamId => _streamId ?? 'unknown';

  // --- Internal State ---
  int _requestIdCounter = 0;
  final Map<int, RawFrame> _pendingFrames = {};

  /// Initialize the plugin
  /// [hostPort]: Port to communicate back to the PluginOrchestrator (Main Isolate)
  /// [config]: Configuration map (model path, thresholds, etc.)
  Future<void> init(
    SendPort hostPort,
    String streamId,
    Map<String, dynamic> config,
  ) async {
    _hostPort = hostPort;
    _streamId = streamId;
    _pluginId = config['pluginId'] ?? 'unknown_plugin';
    await onInit(config);
  }

  /// User-defined initialization
  Future<void> onInit(Map<String, dynamic> config) async {}

  /// Process a raw frame
  /// The plugin should decide to run inference, pass it through, or ignore it.
  Future<void> processFrame(RawFrame frame);

  Future<void> processDirectDetections(
    RawFrame frame,
    List<dynamic> detections,
  ) async {
    final requestId = _requestIdCounter++;
    _pendingFrames[requestId] = frame;

    await handleInferenceResult({
      'requestId': requestId,
      'detections': detections,
      'processingStartMs': frame.decodeTimestamp,
    });
  }

  /// Handle inference results provided by the system
  Future<void> handleInferenceResult(Map<String, dynamic> result);

  /// Dispose plugin resources
  Future<void> dispose() async {
    await onDispose();
  }

  Future<void> onDispose() async {}

  // --- Helper Methods ---

  /// Request inference for a frame
  /// [frame]: The raw frame data
  /// [modelPath]: Path to the model to use (if different from default)
  void requestInference(RawFrame frame, String modelPath) {
    final requestId = _requestIdCounter++;
    _pendingFrames[requestId] = frame;

    _sendToHost({
      'type': 'request_inference',
      'streamId': _streamId,
      'requestId': requestId,
      'modelPath': modelPath,
      'frame': frame.bytes.isEmpty
          ? null
          : TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
      'videoId': frame.nativeVideoId,
    });
  }

  /// Emit a high-level event
  void emitEvent(
    String eventType,
    Map<String, dynamic> data, {
    EventSeverity severity = EventSeverity.info,
  }) {
    _sendToHost({
      'type': 'emit_event',
      'streamId': _streamId,
      'pluginId': _pluginId,
      'eventType': eventType,
      'severity': severity.name,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
  }

  /// Emit a processed frame for display
  /// [detections]: List of detections to overlay
  void emitDisplayFrame(
    RawFrame? frame,
    List<dynamic> detections,
    Map<String, int> timing,
  ) {
    _sendToHost({
      'type': 'emit_display_frame',
      'streamId': _streamId,
      'frame': frame != null
          ? TransferableTypedData.fromList([frame.bytes])
          : null,
      'width': frame?.width ?? 0,
      'height': frame?.height ?? 0,
      'timestamp': frame?.decodeTimestamp ?? timing['decode'] ?? 0,
      'generationTimeMs': frame?.generationTimeMs ?? 0,
      'detections': detections,
      'timing': timing,
    });
  }

  void _sendToHost(dynamic message) {
    _hostPort?.send(message);
  }

  void handleMessage(dynamic message) {
    if (message is Map && message['type'] == 'inference_result') {
      handleInferenceResult(message.cast<String, dynamic>());
    }
  }

  /// Retrieve and remove the pending frame for a given request ID
  RawFrame? getPendingFrame(int requestId) {
    return _pendingFrames.remove(requestId);
  }
}
