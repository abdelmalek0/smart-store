import 'package:smart_store_linux/domain/entities/processed_frame.dart';
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:smart_store_linux/infrastructure/ai/inference_orchestrator.dart';
import 'package:smart_store_linux/domain/entities/raw_frame.dart';
import 'package:smart_store_linux/infrastructure/plugins/plugin_base.dart';
import 'package:smart_store_linux/infrastructure/plugins/implementations/people_counting_plugin.dart';
import 'package:smart_store_linux/infrastructure/plugins/implementations/kitchen_supervision_plugin.dart';
import 'package:smart_store_linux/application/events/events.dart';
import 'package:smart_store_linux/application/events/event_bus_impl.dart';

/// Factory function type for creating plugin instances.
typedef PluginFactory = SmartStorePlugin Function();

/// Registry of available plugin factories.
///
/// To add a new plugin type: add one entry to this map with its plugin ID key.
/// No other code changes required.
final Map<String, PluginFactory> _pluginFactories = {
  'people_counting': () => PeopleCountingPlugin(),
  'kitchen_supervision': () => KitchenSupervisionPlugin(),
};

/// Top-level entry point for Plugin Isolates.
void pluginWorkerEntry(Map<String, dynamic> args) {
  final sendPort = args['sendPort'] as SendPort;
  final pluginType = args['pluginType'] as String?;

  final factory =
      _pluginFactories[pluginType] ?? _pluginFactories['people_counting']!;
  final plugin = factory();

  debugPrint("🧩 PluginIsolate [$pluginType]: Factory created ${plugin.runtimeType}");

  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  int framesProcessed = 0;
  String activeStreamId = "unknown";

  // Using await for ensures sequential processing of messages.
  // Crucially, 'init' will finish before any 'frame' is processed.
  Future<void> runLoop() async {
    await for (final message in receivePort) {
      if (message is! Map) continue;

      try {
        final type = message['type'];

        if (type == 'init') {
          final config = message['config'] as Map<String, dynamic>;
          activeStreamId = message['streamId'] as String;
          debugPrint("🧩 PluginIsolate [$pluginType - $activeStreamId]: Initializing plugin...");
          await plugin.init(sendPort, activeStreamId, config);
          
          // Handshake: Notify host that we are ready
          sendPort.send({'type': 'init_done', 'streamId': activeStreamId});
        } else if (type == 'frame') {
          framesProcessed++;
          if (framesProcessed % 100 == 0) {
            debugPrint("🧩 PluginIsolate [$pluginType - $activeStreamId]: Processed $framesProcessed frames");
          }
          final transferable = message['frame'] as TransferableTypedData?;
          final width = message['width'] as int;
          final height = message['height'] as int;
          final timestamp = message['timestamp'] as int;
          final generationTimeMs = message['generationTimeMs'] as int? ?? 0;
          final bytes = transferable?.materialize().asUint8List() ?? Uint8List(0);
          final nativeVideoId = message['nativeVideoId'] as int?;

          final frame = RawFrame(bytes, width, height, timestamp,
              generationTimeMs: generationTimeMs, nativeVideoId: nativeVideoId);
          await plugin.processFrame(frame);
        } else if (type == 'frame_with_detections') {
          framesProcessed++;
          if (framesProcessed % 100 == 0) {
            debugPrint("🧩 PluginIsolate [$pluginType - $activeStreamId]: Processed $framesProcessed frames (Direct Detections)");
          }
          final transferable = message['frame'] as TransferableTypedData?;
          final width = message['width'] as int;
          final height = message['height'] as int;
          final timestamp = message['timestamp'] as int;
          final detections = message['detections'] as List<dynamic>;
          final bytes = transferable?.materialize().asUint8List() ?? Uint8List(0);
          final nativeVideoId = message['nativeVideoId'] as int?;

          final frame = RawFrame(bytes, width, height, timestamp, nativeVideoId: nativeVideoId);
          await plugin.processDirectDetections(frame, detections);
        } else if (type == 'inference_result') {
          await plugin.handleMessage(message);
        } else if (type == 'dispose') {
          await plugin.dispose();
          receivePort.close();
          break;
        }
      } catch (e, stack) {
        debugPrint("❌ PluginIsolate [$pluginType - $activeStreamId] Error: $e\n$stack");
      }
    }
  }

  runLoop();
}

class PluginRuntime {
  final String streamId;
  String? pluginId; // Track which plugin definition this manager runs
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

  PluginRuntime(this.streamId);

  Future<void> init(Map<String, dynamic> config) async {
    _hostReceivePort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(pluginWorkerEntry, {
        'sendPort': _hostReceivePort!.sendPort,
        'pluginType': config['pluginType'],
      });

      final completer = Completer<SendPort>();
      final initCompleter = Completer<void>();
      
      _hostReceivePort!.listen((message) {
        if (message is SendPort) {
          if (!completer.isCompleted) completer.complete(message);
        } else if (message is Map) {
          if (message['type'] == 'init_done') {
            if (!initCompleter.isCompleted) initCompleter.complete();
          } else {
            _handlePluginMessage(message);
          }
        }
      });

      _isolateSendPort = await completer.future;

      // Initialize Plugin
      _isolateSendPort!.send({
        'type': 'init',
        'streamId': streamId,
        'config': config,
      });

      // WAIT for initialization to finish before allowing frames or returning
      await initCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => debugPrint("⚠️ PluginRuntime [$streamId]: Timeout waiting for init_done"),
      );

      pluginId = config['pluginId'];

      // Listen for global inference results and forward to plugin
      // Only forward results for THIS stream
      _inferenceSubscription = InferenceOrchestrator.instance.resultsStream
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
      debugPrint("Failed to start PluginOrchestrator for $streamId: $e");
    }
  }

  bool _isProcessing = false;
  int _droppedFrames = 0;

  bool processFrame(RawFrame frame) {
    if (_isolateSendPort == null) return false;

    // Leaky Bucket: Drop frame if previous one is still processing
    // This ensures we always process the freshest frame and don't build up a queue
    if (_isProcessing) {
      _droppedFrames++;
      if (_droppedFrames % 100 == 0) {
        debugPrint(
          "PluginRuntime [$streamId]: Inference busy, dropped $_droppedFrames frames",
        );
      }
      return false;
    }

    _isProcessing = true;
    _droppedFrames = 0;

    // Send frame to plugin isolate (Optimization: Skip TransferableTypedData if empty)
    _isolateSendPort!.send({
      'type': 'frame',
      'frame': frame.bytes.isEmpty ? null : TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
      'generationTimeMs': frame.generationTimeMs, 
      'nativeVideoId': frame.nativeVideoId,
    });
    
    return true;
  }

  void processDirectDetections(RawFrame frame, List<dynamic> detections) {
    if (_isolateSendPort == null) return;

    // Send frame + detections to plugin isolate
    _isolateSendPort!.send({
      'type': 'frame_with_detections',
      'frame': frame.bytes.isEmpty ? null : TransferableTypedData.fromList([frame.bytes]),
      'width': frame.width,
      'height': frame.height,
      'timestamp': frame.decodeTimestamp,
      'detections': detections,
      'nativeVideoId': frame.nativeVideoId,
    });
  }

  void _handlePluginMessage(Map message) {
    final type = message['type'];

    if (type == 'request_inference') {
      final requestId = message['requestId'] as int;
      final modelPath = message['modelPath'] as String;
      final transferable = message['frame'] as TransferableTypedData?;
      final width = message['width'] as int;
      final height = message['height'] as int;
      final videoId = message['videoId'] as int?;
      final bytes = transferable?.materialize().asUint8List() ?? Uint8List(0);

      // Call Model Manager (Active Gateway)
      InferenceOrchestrator.instance.requestInference(
        streamId: streamId,
        requestId: requestId,
        modelPath: modelPath,
        imageBytes: bytes,
        width: width,
        height: height,
        videoId: videoId,
      );
    } else if (type == 'emit_display_frame') {
      // stdout.writeln("PluginManager: Received emit_display_frame");
      _isProcessing = false; // Leaky Bucket: ready for next frame

      final transferable = message['frame'] as TransferableTypedData?;
      final width = message['width'] as int;
      final height = message['height'] as int;
      final timestamp = message['timestamp'] as int;
      final detections = message['detections'] as List;
      final timingMap = message['timing'] as Map;
      final generationTimeMs = message['generationTimeMs'] as int? ?? 0;

      final bytes = transferable?.materialize().asUint8List() ?? Uint8List(0);
      final now = DateTime.now().millisecondsSinceEpoch;

      final processed = ProcessedFrame(
        imageBytes: bytes,
        width: width,
        height: height,
        detections: detections.cast<dynamic>(), // ensure dynamic list
        decodeStartMs: timestamp,
        generationTimeMs: generationTimeMs,
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
      EventBusImpl.instance.emit(event);
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
