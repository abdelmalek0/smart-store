import 'dart:async';
import 'dart:isolate';

import 'package:smart_store_linux/core/models/frames.dart';

/// Base class for all SmartStore Plugins
/// Plugins run in their own Isolate.
abstract class SmartStorePlugin {
  SendPort? _hostPort;
  String? _streamId;
  String? _pluginId;

  // --- Internal State ---
  int _requestIdCounter = 0;
  final Map<int, RawFrame> _pendingFrames = {};

  /// Initialize the plugin
  /// [hostPort]: Port to communicate back to the PluginManager (Main Isolate)
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

  /// Process a frame that already has detections (Optimized Path)
  /// Default implementation: Treats it as an inference result
  Future<void> processDirectDetections(
    RawFrame frame,
    List<dynamic> detections,
  ) async {
    // We generate a fake requestId just to map it (internally)
    final requestId = _requestIdCounter++;
    _pendingFrames[requestId] = frame;

    // Direct callback
    await handleInferenceResult({
      'requestId': requestId,
      'detections': detections,
      'processingStartMs': frame.decodeTimestamp, // Approx
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
      'frame': TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
    });
  }

  /// Emit a high-level event
  void emitEvent(String eventType, Map<String, dynamic> data) {
    _sendToHost({
      'type': 'emit_event',
      'streamId': _streamId,
      'pluginId': _pluginId,
      'eventType': eventType,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
  }

  /// Emit a processed frame for display
  /// [detections]: List of detections to overlay
  void emitDisplayFrame(
    RawFrame frame,
    List<dynamic> detections,
    Map<String, int> timing,
  ) {
    _sendToHost({
      'type': 'emit_display_frame',
      'streamId': _streamId,
      // optimized: send detection data, original frame might be cached on host or we send it back
      'frame': TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
      'detections': detections,
      'timing': timing,
    });
  }

  void _sendToHost(dynamic message) {
    _hostPort?.send(message);
  }

  /// Handle internal messages (like inference results)
  /// This is called by the PluginIsolate entry point
  void handleMessage(dynamic message) {
    if (message is Map && message['type'] == 'inference_result') {
      // handleInferenceResult(message) is abstract, implemented by subclass
      handleInferenceResult(message.cast<String, dynamic>());
    }
  }

  /// Retrieve and remove the pending frame for a given request ID
  RawFrame? getPendingFrame(int requestId) {
    return _pendingFrames.remove(requestId);
  }
}
