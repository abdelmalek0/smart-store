import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/core/config/constants.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/models/rtsp_stream.dart';
import 'package:smart_store_linux/ai/inference/service/inference_service.dart';
import 'package:smart_store_linux/backend/streaming/isolates/capture_isolate.dart';
import 'package:smart_store_linux/backend/streaming/isolates/isolate_params.dart';
import 'package:smart_store_linux/backend/services/video/ffmpeg_video_service.dart';
import 'package:smart_store_linux/plugins/manager/plugin_manager.dart'; // Add PluginManager
import 'package:smart_store_linux/backend/services/config_service.dart'; // Add ConfigService
import 'package:smart_store_linux/core/registry/plugin_registry.dart';

/// Headless stream processor that manages video capture, inference, and display queues
///
/// Architecture:
/// - Capture: Runs in isolate, decodes video frames
/// - InferenceQueue (max 2): Buffers raw frames for inference
/// - DisplayQueue (max 10): Buffers processed frames with detections
/// - Display: Outputs frames for UI rendering
class StreamProcessor {
  final RTSPStream stream;
  // modelPath removed from member fields as it is now dynamic in Plugin Config
  int _nativeVideoId = 0;
  int? _textureId;
  int _frameWidth = 0;
  int _frameHeight = 0;
  bool _isActive = true;

  // Freeze mode - stop inference but keep displaying raw frames
  bool _isFrozen = false;

  // Queue Configuration - Using centralized Constants for consistency
  static const int inferenceQueueMaxSize = 5;
  static const int displayQueueMaxSize = Constants.displayQueueMaxSize;

  // Plugin Manager (replaces Inference and Display Queue logic somewhat)
  PluginManager? _pluginManager;

  // StreamProcessor no longer manages InferenceQueue directly as Plugin handles it.
  // It still manages DisplayQueue for backpressure control before rendering.

  // DisplayQueue: Buffers processed frames with detections (max 10)
  final Queue<ProcessedFrame> _displayQueue = Queue<ProcessedFrame>();

  // Note: _inferenceQueue removed as PluginManager handles frame buffering/injest

  final StreamController<ProcessedFrame> _frameStreamController =
      StreamController<ProcessedFrame>.broadcast();

  // Events
  final StreamController<Map<String, dynamic>> _eventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventStreamController.stream;

  Stream<ProcessedFrame> get frameStream => _frameStreamController.stream;
  bool get isInitialized => _nativeVideoId > 0;
  int get nativeVideoId => _nativeVideoId; // Expose for texture linking
  int? get textureId => _textureId;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;

  // Model labels extracted from ONNX metadata (received from capture isolate)
  Map<int, String> _modelLabels = {};
  Map<int, String> get modelLabels => _modelLabels;
  bool get isFrozen => _isFrozen;

  // Isolate for frame capture
  Isolate? _captureIsolate;
  ReceivePort? _captureReceivePort;
  SendPort? _captureCommandPort;

  // Stats
  int _pendingPluginFrames = 0; // Backpressure tracking for Plugin
  StreamSubscription?
  _pluginFrameSubscription; // Listen to Plugin processed frames
  StreamSubscription? _pluginEventSubscription; // Listen to Plugin events

  bool _isPluginActive = false; // Flag to track if plugin is running

  StreamProcessor({required this.stream});

  /// Initialize the processor and start all loops
  Future<void> initialize() async {
    try {
      debugPrint("Starting Stream Processor for stream: ${stream.id}");

      // Initialize Plugin Manager
      _pluginManager = PluginManager(stream.id);

      // 1. Resolve Active Plugin
      // Defaults to 'people_counting' if not set
      var pluginId =
          ConfigService.instance.getStreamActivePlugin(stream.id) ??
          'people_counting';

      // 2. Get Plugin Configuration
      // Start with global defaults
      var config = ConfigService.instance.getGlobalPluginConfig(pluginId) ?? {};

      // Overlay stream-specific configuration if available
      final streamConfig = ConfigService.instance.getPluginConfig(
        stream.id,
        pluginId,
      );
      if (streamConfig != null) {
        config.addAll(streamConfig);
      }

      // Check for valid model path - STOP if missing
      // We do NOT apply a default fallback anymore per user request.
      final modelPath = config['modelPath'] as String?;

      if (modelPath == null || modelPath.isEmpty) {
        debugPrint(
          "⚠️ No model assigned for stream ${stream.id}. Plugin will NOT start.",
        );
        _isPluginActive = false;
        // We still start the read loop to show video, but skip plugin/inference init
        _startReadLoop(null); // Pass null modelPath
        return;
      }

      _isPluginActive = true;
      debugPrint("✓ Model assigned: $modelPath. Starting Plugin.");

      // Apply default config from registry
      final registeredPlugin = PluginRegistry.findById(pluginId);
      if (registeredPlugin != null) {
        for (final entry in registeredPlugin.defaultConfig.entries) {
          config.putIfAbsent(entry.key, () => entry.value);
        }
      }

      // Ensure pluginId is set in config
      config['pluginId'] = pluginId;

      // Ensure pluginType is set for PluginManager
      config['pluginType'] = pluginId;

      // Ensure model is loaded in InferenceService (Safe to call multiple times)
      await InferenceService.instance.loadModel(modelPath);

      // Configuration for plugin (pass model path as requested)
      await _pluginManager!.init(config);

      // Listen for processed frames from Plugin
      _pluginFrameSubscription = _pluginManager!.processedFrameStream.listen((
        processedFrame,
      ) {
        if (_pendingPluginFrames > 0) _pendingPluginFrames--;

        // Add to DisplayQueue (Backpressure logic)
        if (_displayQueue.length >= displayQueueMaxSize) {
          _displayQueue.removeFirst();
        }
        _displayQueue.add(processedFrame);
      });

      // Listen for Events
      _pluginEventSubscription = _pluginManager!.eventStream.listen((event) {
        _eventStreamController.add(event);
      });

      _startReadLoop(modelPath);
      // No separate inference loop needed - Capture loop pushes directly to Plugin
    } catch (e) {
      debugPrint("Error initializing processor for ${stream.id}: $e");
    }
  }

  /// Start the read loop (capture isolate)
  void _startReadLoop(String? modelPath) async {
    _captureReceivePort = ReceivePort();
    try {
      debugPrint('SPM: Spawning isolate with modelPath=$modelPath');
      _captureIsolate = await Isolate.spawn(
        captureLoop,
        IsolateInitParams(
          _captureReceivePort!.sendPort,
          stream.url,
          RootIsolateToken.instance!,
          modelPath: modelPath, // Pass the model path (can be null)
        ),
      );
      _captureReceivePort!.listen((message) {
        try {
          RawFrame? frame;

          if (message is Map &&
              message.containsKey('type') &&
              message['type'] == 'init') {
            // Initial handshake with command port
            if (message.containsKey('commandPort')) {
              _captureCommandPort = message['commandPort'] as SendPort;
              debugPrint("✓ Received command port from capture isolate");
            }
            return;
          }

          if (message is RawFrame) {
            frame = message;
          } else if (message is List && message.isNotEmpty) {
            final msgType = message[0];

            if (msgType == 'detections_only') {
              // ... existing optimization logic ...
              // If we are here, something sent detections.
              // Should not happen if plugin inactive, but standard handling applies.
              final width = message[1] as int;
              final height = message[2] as int;
              final timestamp = message[3] as int;
              final detections = message[4] as List<dynamic>;
              final inferenceTime = (message.length > 5)
                  ? message[5] as double
                  : 0.0;

              final now = DateTime.now().millisecondsSinceEpoch;

              final processed = ProcessedFrame(
                imageBytes: Uint8List(0), // Empty - no video rendering
                width: width,
                height: height,
                detections: detections,
                decodeStartMs: timestamp,
                preprocessEndMs: now - inferenceTime.toInt(),
                inferenceEndMs: now,
                postprocessEndMs: now,
              );

              if (_displayQueue.length >= displayQueueMaxSize) {
                _displayQueue.removeFirst();
              }
              _displayQueue.add(processed);
            } else if (msgType == 'frame') {
              // Handle TransferableTypedData Optimization
              final transferable = message[1] as TransferableTypedData;
              final width = message[2] as int;
              final height = message[3] as int;
              final timestamp = message[4] as int;

              final bytes = transferable.materialize().asUint8List();
              frame = RawFrame(bytes, width, height, timestamp);
            } else if (msgType == 'processed_frame') {
              // Optimized Linux Path: Frame + Inference received together
              // ... existing logic ...
              if (_displayQueue.length >= displayQueueMaxSize) {
                return; // Backpressure
              }

              final transferable = message[1] as TransferableTypedData;
              final width = message[2] as int;
              final height = message[3] as int;
              final timestamp = message[4] as int;
              final detections = message[5] as List<dynamic>;
              final inferenceTime = (message.length > 6)
                  ? message[6] as double
                  : 0.0; // message[6]

              final bytes = transferable.materialize().asUint8List();
              final now = DateTime.now().millisecondsSinceEpoch;

              final processed = ProcessedFrame(
                imageBytes: bytes,
                width: width,
                height: height,
                detections: detections,
                decodeStartMs: timestamp,
                preprocessEndMs: now - inferenceTime.toInt(),
                inferenceEndMs: now,
                postprocessEndMs: now,
              );

              // If plugin active, route through it
              if (_isPluginActive && !_isFrozen && _pluginManager != null) {
                final frame = RawFrame(bytes, width, height, timestamp);
                if (_pendingPluginFrames < 2) {
                  _pendingPluginFrames++;
                  _pluginManager!.processDirectDetections(frame, detections);
                }
              } else {
                // PASS-THROUGH (Plugin Inactive) or Frozen
                // Just display the frame
                if (processed.width > 0) {
                  _frameWidth = processed.width;
                  _frameHeight = processed.height;
                }
                _displayQueue.add(processed);
              }
            } else if (msgType == 'labels') {
              final labelsMap = message[1] as Map<int, String>;
              _modelLabels = labelsMap;
              debugPrint(
                "📋 StreamProcessor: Received ${labelsMap.length} model labels",
              );
            } else {
              debugPrint("Main: Unknown list message type: '$msgType'");
            }
          } else if (message is Map && message.containsKey('videoId')) {
            _nativeVideoId = message['videoId'] as int;
            _textureId = message['textureId'] as int;
            debugPrint(
              "Stream Processor: Received Init Message. VideoID: $_nativeVideoId, TextureID: $_textureId",
            );
          } else if (message is int) {
            _nativeVideoId = message;
          } else {
            debugPrint(
              "Main: Received unknown message type: ${message.runtimeType}",
            );
          }

          if (frame != null) {
            // Forward to Plugin Manager with Backpressure
            if (_isPluginActive && !_isFrozen && _pendingPluginFrames < 2) {
              _pendingPluginFrames++;
              _pluginManager?.processFrame(frame);
            } else if (!_isPluginActive) {
              // PASS-THROUGH: No plugin, just display raw frame
              final now = DateTime.now().millisecondsSinceEpoch;
              final processed = ProcessedFrame(
                imageBytes: frame.bytes,
                width: frame.width,
                height: frame.height,
                detections: [], // Empty detections
                decodeStartMs: frame.decodeTimestamp,
                preprocessEndMs: now,
                inferenceEndMs: now,
                postprocessEndMs: now,
              );

              if (frame.width > 0) {
                _frameWidth = frame.width;
                _frameHeight = frame.height;
              }

              if (_displayQueue.length < displayQueueMaxSize) {
                _displayQueue.add(processed);
              }
            } else {
              // Drop frame (Backpressure or Frozen+PluginActive but dropping?)
            }
          }
        } catch (e, st) {
          debugPrint("Main: Error parsing isolate message: $e\n$st");
        }
      });

      // Start display loop separately
      _startDisplayLoop();
    } catch (e) {
      debugPrint("Failed to spawn capture isolate: $e");
    }
  }

  // Inference Loop Removed - Logic moved to Plugin Manager

  // --- Performance Tracking ---
  int _displayCount = 0;
  Timer? _perfTimer;

  void _startPerfLogging() {
    _perfTimer?.cancel();
    _perfTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }
      // FPS calculation logic temporarily disabled or removed if unused
      _displayCount = 0;
    });
  }

  /// Display loop: Sequentially display frames from DisplayQueue or InferenceQueue
  /// When frozen (stopped): Display raw frames from InferenceQueue (no inference)
  /// When running: Display ONLY processed frames from DisplayQueue (with matching detections)
  void _startDisplayLoop() async {
    // Start performance logging
    _startPerfLogging();

    while (_isActive) {
      ProcessedFrame? frameToDisplay;

      try {
        // When FROZEN (engine stopped): Logic needed?
        // Plugin shouldn't run inference, but should probably pass through frames.
        // For now, if Frozen, just pause display queue consumption or clear detections.
        if (_isFrozen) {
          // If frozen, we might want to just show the frames coming from plugin WITHOUT inference?
          // But Plugin handles everything.
          // Simplest: Just consume display queue. The Plugin should have stopped emitting events/inference if configured.
          // For now, treat frozen as "Consume Display Queue but ignore new plugin outputs?"
          // Or rely on PluginManager to handle freeze.

          // Legacy behavior: Show raw frame.
          // Since Plugin is "middleman", validation: Does plugin pass through if we stop inference?
          // Not yet implemented.
          // Fallback: If frozen, clear detections on frames being displayed.
        }

        if (_displayQueue.isNotEmpty) {
          frameToDisplay = _displayQueue.removeFirst();
          if (_isFrozen) {
            // Remove detections if frozen
            frameToDisplay = ProcessedFrame(
              imageBytes: frameToDisplay.imageBytes,
              width: frameToDisplay.width,
              height: frameToDisplay.height,
              detections: [],
              decodeStartMs: frameToDisplay.decodeStartMs,
              preprocessEndMs: frameToDisplay.preprocessEndMs,
              inferenceEndMs: frameToDisplay.inferenceEndMs,
              postprocessEndMs: frameToDisplay.postprocessEndMs,
            );
          }
        }
        // When RUNNING: ONLY show frames from DisplayQueue (synchronized with detections)

        // Send to display stream
        if (frameToDisplay != null && !_frameStreamController.isClosed) {
          _frameStreamController.add(frameToDisplay);
          _displayCount++; // Track display count
          if (_displayCount % 30 == 0) {
            debugPrint(
              "SPM: Display loop emitting frame #${_displayCount}. Q: ${_displayQueue.length}",
            );
          }
        }
      } catch (e) {
        debugPrint("SPM: Error in display loop: $e");
      }

      // Adaptive timing: display frames as they arrive without forced delays
      if (frameToDisplay != null) {
        // Frame displayed, check for next immediately
        await Future.delayed(Duration.zero);
      } else {
        // No frame available, wait briefly before checking again
        await Future.delayed(const Duration(milliseconds: 8));
      }
    }
    _perfTimer?.cancel();
  }

  /// Freeze processor - stop inference but keep displaying raw frames
  void freeze() {
    if (_isFrozen) return;
    debugPrint("Freezing processor for ${stream.id} - stopping inference only");

    _isFrozen = true;

    // Stop inference subscription - no more detection processing
    // _inferenceSubscription?.cancel(); // No longer used
    // _inferenceSubscription = null;

    // We should tell Plugin to stop inference?
    // For now, simply ignoring detections in display loop.

    // Clear detections so display shows raw frames without overlays

    // Note: _isActive remains true to keep capture and display running
    // Display loop will automatically switch to showing raw frames from InferenceQueue

    debugPrint(
      "Processor frozen for ${stream.id} - now showing raw video feed",
    );
  }

  /// Unfreeze processor - restart inference subscription
  void unfreeze() {
    if (!_isFrozen) return;
    debugPrint("Unfreezing processor for ${stream.id} - restarting inference");

    _isFrozen = false;

    // Restart inference subscription
    // Re-enable in Plugin?
    // For now, just flag update.
    debugPrint(
      "Unfreezing processor... (Plugin logic needs update for true freeze)",
    );

    debugPrint("Processor unfrozen for ${stream.id} - inference restarted");
  }

  Future<bool> showFrame(int timestamp) async {
    if (_nativeVideoId > 0) {
      return await FFmpegVideoService.showFrame(_nativeVideoId, timestamp);
    }
    return false;
  }

  /// Dispose the processor and release all resources
  Future<void> dispose() async {
    debugPrint("Disposing processor for ${stream.id}");

    _isActive = false;
    _isFrozen = false;

    // Stop capture if still running
    if (_captureReceivePort != null) {
      _captureReceivePort?.close();
      _captureReceivePort = null;
    }

    // Gracefully stop isolate
    if (_captureCommandPort != null) {
      debugPrint("Sending STOP command to capture isolate...");
      _captureCommandPort?.send('STOP');
      // Give it a moment to release native locks
      await Future.delayed(const Duration(milliseconds: 500));
      _captureCommandPort = null;
    }

    if (_captureIsolate != null) {
      _captureIsolate?.kill(priority: Isolate.immediate);
      _captureIsolate = null;
    }

    // Stop inference subscriptions
    _pluginFrameSubscription?.cancel();
    _pluginEventSubscription?.cancel();
    _pluginManager?.dispose();
    _eventStreamController.close();

    // Release video only if it was opened
    if (_nativeVideoId > 0) {
      try {
        NativeInferenceService().videoRelease(_nativeVideoId);
        debugPrint("Video released for ${stream.id}");
      } catch (e) {
        debugPrint("Error releasing video for ${stream.id}: $e");
      }
      _nativeVideoId = 0;
    }

    // Close stream
    if (!_frameStreamController.isClosed) {
      _frameStreamController.close();
    }

    debugPrint("Processor disposed for ${stream.id}");
  }
}
