import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/ai/service/inference_service.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/plugins/plugin_base.dart';
import 'package:smart_store_linux/core/plugins/impl/people_counting_plugin.dart';
import 'package:smart_store_linux/core/plugins/impl/kitchen_supervision_plugin.dart';
import 'package:smart_store_linux/core/events/events.dart';
import 'package:smart_store_linux/core/events/event_service.dart';

/// Top-level entry point for Plugin Isolates
void pluginIsolateEntry(Map<String, dynamic> args) {
  final sendPort = args['sendPort'] as SendPort;
  final pluginType = args['pluginType'] as String?;

  SmartStorePlugin plugin;
  if (pluginType == 'kitchen_supervision') {
    plugin = KitchenSupervisionPlugin();
  } else {
    // Default
    plugin = PeopleCountingPlugin();
  }

  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is Map) {
      if (message['type'] == 'init') {
        // stdout.writeln("PluginIsolate: Init received");
        final config = message['config'] as Map<String, dynamic>;
        final streamId = message['streamId'] as String;
        plugin.init(sendPort, streamId, config);
      } else if (message['type'] == 'frame') {
        // Frame received
        final transferable = message['frame'] as TransferableTypedData;
        final width = message['width'] as int;
        final height = message['height'] as int;
        final timestamp = message['timestamp'] as int;
        final bytes = transferable.materialize().asUint8List();

        final frame = RawFrame(bytes, width, height, timestamp);
        plugin.processFrame(frame);
      } else if (message['type'] == 'frame_with_detections') {
        // Optimized path: Frame + Detections
        final transferable = message['frame'] as TransferableTypedData;
        final width = message['width'] as int;
        final height = message['height'] as int;
        final timestamp = message['timestamp'] as int;
        final detections = message['detections'] as List<dynamic>;
        final bytes = transferable.materialize().asUint8List();

        final frame = RawFrame(bytes, width, height, timestamp);
        plugin.processDirectDetections(frame, detections);
      } else if (message['type'] == 'inference_result') {
        // stdout.writeln("PluginIsolate: Inference Result Received");
        plugin.handleMessage(message);
      } else if (message['type'] == 'dispose') {
        plugin.dispose();
        receivePort.close();
      }
    }
  });
}

class PluginManager {
  final String streamId;
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _hostReceivePort;

  // Output streams
  final StreamController<ProcessedFrame> _processedFrameController =
      StreamController.broadcast();
  Stream<ProcessedFrame> get processedFrameStream =>
      _processedFrameController.stream;

  // Event stream removed - using EventService

  StreamSubscription? _inferenceSubscription;

  PluginManager(this.streamId);

  Future<void> init(Map<String, dynamic> config) async {
    _hostReceivePort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(pluginIsolateEntry, {
        'sendPort': _hostReceivePort!.sendPort,
        'pluginType': config['pluginType'],
      });

      final completer = Completer<SendPort>();
      _hostReceivePort!.listen((message) {
        if (message is SendPort) {
          if (!completer.isCompleted) completer.complete(message);
        } else if (message is Map) {
          _handlePluginMessage(message);
        }
      });

      _isolateSendPort = await completer.future;

      // Initialize Plugin
      _isolateSendPort!.send({
        'type': 'init',
        'streamId': streamId,
        'config': config,
      });

      // Listen for global inference results and forward to plugin
      // Only forward results for THIS stream
      _inferenceSubscription = InferenceService.instance.resultsStream
          .where((r) => r.streamId == streamId)
          .listen((result) {
            _isolateSendPort!.send({
              'type': 'inference_result',
              'requestId': result.requestId,
              'detections': result.detections,
              'processingStartMs': result.processingStartMs,
            });
          });
    } catch (e) {
      debugPrint("Failed to start PluginManager for $streamId: $e");
    }
  }

  void processFrame(RawFrame frame) {
    if (_isolateSendPort == null) return;

    // Send frame to plugin isolate
    _isolateSendPort!.send({
      'type': 'frame',
      'frame': TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
    });
  }

  void processDirectDetections(RawFrame frame, List<dynamic> detections) {
    if (_isolateSendPort == null) return;

    // Send frame + detections to plugin isolate
    _isolateSendPort!.send({
      'type': 'frame_with_detections',
      'frame': TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
      'detections': detections,
    });
  }

  void _handlePluginMessage(Map message) {
    final type = message['type'];

    if (type == 'request_inference') {
      // stdout.writeln("PluginManager: Received request_inference");
      final requestId = message['requestId'] as int;
      final modelPath = message['modelPath'] as String;
      final transferable = message['frame'] as TransferableTypedData;
      final width = message['width'] as int;
      final height = message['height'] as int;
      final bytes = transferable.materialize().asUint8List();

      // Call Inference Service (Main Isolate)
      InferenceService.instance.enqueueFrame(
        streamId,
        requestId,
        modelPath,
        bytes,
        width,
        height,
      );
    } else if (type == 'emit_display_frame') {
      // stdout.writeln("PluginManager: Received emit_display_frame");
      final transferable = message['frame'] as TransferableTypedData;
      final width = message['width'] as int;
      final height = message['height'] as int;
      final timestamp = message['timestamp'] as int;
      final detections = message['detections'] as List;
      final timingMap = message['timing'] as Map;

      final bytes = transferable.materialize().asUint8List();
      final now = DateTime.now().millisecondsSinceEpoch;

      final processed = ProcessedFrame(
        imageBytes: bytes,
        width: width,
        height: height,
        detections: detections.cast<dynamic>(), // ensure dynamic list
        decodeStartMs: timestamp,
        preprocessEndMs: now, // approx
        inferenceEndMs: now - (timingMap['inference'] as int? ?? 0),
        postprocessEndMs: now,
      );

      _processedFrameController.add(processed);
    } else if (type == 'emit_event') {
      // stdout.writeln("[EVENT LOG] ${message['eventType']}: ${message['data']}");

      // Construct AppEvent from Map
      final severityStr = message['severity'] as String?; // Extract severity

      final event = DetectionEvent(
        eventId: DateTime.now().millisecondsSinceEpoch
            .toString(), // Generating ID if missing
        timestamp: DateTime.now().millisecondsSinceEpoch,
        streamId: streamId,
        type: message['eventType'] ?? 'unknown',
        severity: EventSeverity.fromString(severityStr), // Use factory
        label: message['data'] != null
            ? message['data']['label'] ?? 'unknown'
            : 'unknown',
        confidence: message['data'] != null
            ? (message['data']['confidence'] ?? 0.0)
            : 0.0,
        metadata: message['data'] ?? {},
      );

      // Emit globally
      EventService.instance.emit(event);
      debugPrint("[EVENT] Global Emit: ${event.type} - ${event.label}");
    }
  }

  void dispose() {
    _isolateSendPort?.send({'type': 'dispose'});
    _inferenceSubscription?.cancel();
    _isolate?.kill();
    _hostReceivePort?.close();
    _processedFrameController.close();
    // _eventController removed
  }
}
