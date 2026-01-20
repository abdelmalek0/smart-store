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
import 'package:smart_store_linux/backend/services/ffmpeg_video_service.dart';

/// Headless stream processor that manages video capture, inference, and display queues
///
/// Architecture:
/// - Capture: Runs in isolate, decodes video frames
/// - InferenceQueue (max 2): Buffers raw frames for inference
/// - DisplayQueue (max 10): Buffers processed frames with detections
/// - Display: Outputs frames for UI rendering
class StreamProcessor {
  final RTSPStream stream;
  final String modelPath;
  int _nativeVideoId = 0;
  int? _textureId;
  bool _isActive = true;

  // Freeze mode - stop inference but keep displaying raw frames
  bool _isFrozen = false;

  // Queue Configuration - Using centralized Constants for consistency
  static const int INFERENCE_QUEUE_MAX_SIZE =
      Constants.inferenceQueueMaxSize;
  static const int DISPLAY_QUEUE_MAX_SIZE =
      Constants.displayQueueMaxSize;

  // InferenceQueue: Buffers raw frames from capture (max 3)
  // Purpose: Maintain smooth playback even if inference is slower than capture
  final Queue<RawFrame> _inferenceQueue = Queue<RawFrame>();

  // DisplayQueue: Buffers processed frames with detections (max 10)
  // Purpose: Sequential display with frame dropping if inference is too fast
  final Queue<ProcessedFrame> _displayQueue = Queue<ProcessedFrame>();

  final StreamController<ProcessedFrame> _frameStreamController =
      StreamController<ProcessedFrame>.broadcast();

  Stream<ProcessedFrame> get frameStream => _frameStreamController.stream;
  bool get isInitialized => _nativeVideoId > 0;
  int get nativeVideoId => _nativeVideoId; // Expose for texture linking
  int? get textureId => _textureId;
  bool get isFrozen => _isFrozen;

  // Isolate for frame capture
  Isolate? _captureIsolate;
  ReceivePort? _captureReceivePort;

  // Stats
  int _inferenceFrameCounter = 0;
  List<dynamic> _lastDetections = [];
  StreamSubscription? _inferenceSubscription;
  int _requestIdCounter = 0;
  int _pendingInferenceCount = 0; // Backpressure tracking

  // Map to store frames by requestId for proper frame-detection pairing
  final Map<int, RawFrame> _pendingFrames = {};

  // Map to store timestamps for pipeline FPS calculation
  final Map<int, Map<String, int>> _frameTimestamps = {};

  StreamProcessor({required this.stream, required this.modelPath});

  /// Initialize the processor and start all loops
  Future<void> initialize() async {
    try {
      debugPrint("Starting Native Processor for stream: ${stream.id}");

      // Listen for inference results
      _inferenceSubscription = InferenceService.instance.resultsStream
          .where((result) => result.streamId == stream.id)
          .listen((result) {
            // Update latest detections
            _lastDetections = result.detections;
            if (_pendingInferenceCount > 0) _pendingInferenceCount--;

            // Get the ACTUAL frame that was inferenced (stored by requestId)
            final inferredFrame = _pendingFrames.remove(result.requestId);
            final timestamps = _frameTimestamps.remove(result.requestId);

            if (inferredFrame != null && timestamps != null) {
              final now = DateTime.now().millisecondsSinceEpoch;

              // Create ProcessedFrame with matching frame and detections
              final processedFrame = ProcessedFrame(
                imageBytes: inferredFrame.bytes,
                width: inferredFrame.width,
                height: inferredFrame.height,
                detections: List.from(_lastDetections),
                decodeStartMs: timestamps['decodeStart']!,
                preprocessEndMs: result
                    .processingStartMs, // When processing actually started (no queue wait)
                inferenceEndMs: now, // Inference just completed
                postprocessEndMs:
                    now, // Post-processing is minimal (just copying detections)
              );

              // Add to DisplayQueue (max size 10)
              // Drop oldest if full
              if (_displayQueue.length >= DISPLAY_QUEUE_MAX_SIZE) {
                _displayQueue.removeFirst();
              }
              _displayQueue.add(processedFrame);
            }
          });

      _startReadLoop();
      _startInferenceLoop();
    } catch (e) {
      debugPrint("Error initializing processor for ${stream.id}: $e");
    }
  }

  /// Start the read loop (capture isolate)
  void _startReadLoop() async {
    _captureReceivePort = ReceivePort();
    try {
      debugPrint('SPM: Spawning isolate with modelPath=$modelPath');
      _captureIsolate = await Isolate.spawn(
        captureLoop,
        IsolateInitParams(
          _captureReceivePort!.sendPort,
          stream.url,
          RootIsolateToken.instance!,
          modelPath: modelPath, // Pass the model path
        ),
      );
      _captureReceivePort!.listen((message) {
        try {
          RawFrame? frame;

          if (message is RawFrame) {
            frame = message;
          } else if (message is List && message.isNotEmpty) {
            final msgType = message[0];

            if (msgType == 'detections_only') {
              // Optimized: Detections WITHOUT frame bytes
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

              if (_displayQueue.length >= DISPLAY_QUEUE_MAX_SIZE) {
                _displayQueue.removeFirst();
              }
              _displayQueue.add(processed);
              _inferenceFrameCounter++;
            } else if (msgType == 'frame') {
              // Handle TransferableTypedData Optimization
              final transferable = message[1] as TransferableTypedData;
              final width = message[2] as int;
              final height = message[3] as int;
              final timestamp = message[4] as int;

              final bytes = transferable.materialize().asUint8List();
              frame = RawFrame(bytes, width, height, timestamp);
              _captureCount++; // Track capture count (moved here)
            } else if (msgType == 'processed_frame') {
              // Optimized Linux Path: Frame + Inference received together

              //'t Backpressure: If display queue is full, drop frame BEFORE materializing bytes
              // This saves massive GC pressure
              if (_displayQueue.length >= DISPLAY_QUEUE_MAX_SIZE) {
                debugPrint(
                  "SPM: Dropping frame (Backpressure) - Q: ${_displayQueue.length}",
                );
                return;
              }

              final transferable = message[1] as TransferableTypedData;
              final width = message[2] as int;
              final height = message[3] as int;
              final timestamp = message[4] as int;
              final detections = message[5] as List<dynamic>;
              final inferenceTime = (message.length > 6)
                  ? message[6] as double
                  : 0.0;

              // Only materialize if we are going to use it
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

              _displayQueue.add(processed);
              _captureCount++; // Fix: Also count processed_frame as captured
              _inferenceFrameCounter++;
            } else {
              debugPrint("Main: Unknown list message type: '$msgType'");
            }
          } else if (message is Map && message.containsKey('videoId')) {
            _nativeVideoId = message['videoId'] as int;
            _textureId = message['textureId'] as int;
            debugPrint(
              "Stream Processor: Initialized with Texture ID $_textureId",
            );
          } else if (message is int) {
            _nativeVideoId = message;
          } else {
            debugPrint(
              "Main: Received unknown message type: ${message.runtimeType}",
            );
          }

          if (frame != null) {
            // Add to InferenceQueue (max size 2)
            // Always keep the latest frames, drop oldest if full
            if (_inferenceQueue.length >= INFERENCE_QUEUE_MAX_SIZE) {
              _inferenceQueue.removeFirst(); // Drop oldest
            }
            _inferenceQueue.add(frame);
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

  /// Start the inference loop
  void _startInferenceLoop() async {
    while (_isActive) {
      if (_inferenceQueue.isNotEmpty) {
        try {
          // LATEST FRAME SELECTION: Always use the most recent frame
          // This prioritizes real-time responsiveness over processing all frames
          final RawFrame frame = _inferenceQueue.last;
          _inferenceQueue.clear(); // Clear queue, we only process latest

          _inferenceFrameCounter++;

          // Minimal backpressure for ultra-low latency
          // Only allow 1 frame in flight at a time
          if (_pendingInferenceCount < 1) {
            final requestId = _requestIdCounter++;
            _pendingInferenceCount++;

            final now = DateTime.now().millisecondsSinceEpoch;

            // Store the frame we're sending for inference
            _pendingFrames[requestId] = frame;

            // Store timestamps for FPS calculation
            _frameTimestamps[requestId] = {
              'decodeStart':
                  frame.decodeTimestamp, // Actual decode timestamp from video
              'preprocessEnd':
                  now, // We're about to send for inference (not used anymore)
            };

            InferenceService.instance.enqueueFrame(
              stream.id,
              requestId,
              modelPath,
              frame.bytes,
              frame.width,
              frame.height,
            );
          }
        } catch (e) {
          debugPrint("SPM: Error in inference loop: $e");
        }
      }

      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  // --- Performance Tracking ---
  int _captureCount = 0;
  int _displayCount = 0;
  Timer? _perfTimer;

  void _startPerfLogging() {
    _perfTimer?.cancel();
    _perfTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }
      final captureFps = (_captureCount / 2).toStringAsFixed(1);
      final inferenceFps = (_inferenceFrameCounter / 2).toStringAsFixed(1);
      final displayFps = (_displayCount / 2).toStringAsFixed(1);

      debugPrint(
        "📊 Stats [${stream.id}]: "
        "Capture: ${captureFps}fps | "
        "Inference: ${inferenceFps}fps | "
        "Display: ${displayFps}fps | "
        "Pending: $_pendingInferenceCount",
      );

      _captureCount = 0;
      _inferenceFrameCounter = 0;
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
        // When FROZEN (engine stopped): Show raw frames from InferenceQueue
        if (_isFrozen && _inferenceQueue.isNotEmpty) {
          final rawFrame = _inferenceQueue
              .removeFirst(); // FIX: Remove frame to prevent reuse
          final now = DateTime.now().millisecondsSinceEpoch;
          frameToDisplay = ProcessedFrame(
            imageBytes: rawFrame.bytes,
            width: rawFrame.width,
            height: rawFrame.height,
            detections: [], // No detections when stopped
            decodeStartMs: now,
            preprocessEndMs: now,
            inferenceEndMs: now,
            postprocessEndMs: now,
          );
        }
        // When RUNNING: ONLY show frames from DisplayQueue (synchronized with detections)
        // Do NOT fallback to InferenceQueue to prevent showing new frames with old bboxes
        else if (!_isFrozen && _displayQueue.isNotEmpty) {
          frameToDisplay = _displayQueue.removeFirst();
        }
        // If DisplayQueue is empty during inference, skip this frame
        // This ensures we only show frames that have matching detections

        // Send to display stream
        if (frameToDisplay != null && !_frameStreamController.isClosed) {
          _frameStreamController.add(frameToDisplay);
          _displayCount++; // Track display count
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
    _inferenceSubscription?.cancel();
    _inferenceSubscription = null;

    // Clear detections so display shows raw frames without overlays
    _lastDetections = [];

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
    _inferenceSubscription = InferenceService.instance.resultsStream
        .where((result) => result.streamId == stream.id)
        .listen((result) {
          _lastDetections = result.detections;
          if (_pendingInferenceCount > 0) _pendingInferenceCount--;

          if (_inferenceQueue.isNotEmpty) {
            final latestFrame = _inferenceQueue.last;
            final now = DateTime.now().millisecondsSinceEpoch;
            final processedFrame = ProcessedFrame(
              imageBytes: latestFrame.bytes,
              width: latestFrame.width,
              height: latestFrame.height,
              detections: List.from(_lastDetections),
              decodeStartMs: now - 10, // Approximation
              preprocessEndMs: now - 5,
              inferenceEndMs: now,
              postprocessEndMs: now,
            );

            if (_displayQueue.length >= DISPLAY_QUEUE_MAX_SIZE) {
              _displayQueue.removeFirst();
            }
            _displayQueue.add(processedFrame);
          }
        });

    debugPrint("Processor unfrozen for ${stream.id} - inference restarted");
  }

  Future<void> showFrame(int timestamp) async {
    if (_nativeVideoId > 0) {
      await FFmpegVideoService.showFrame(_nativeVideoId, timestamp);
    }
  }

  /// Dispose the processor and release all resources
  void dispose() {
    debugPrint("Disposing processor for ${stream.id}");

    _isActive = false;
    _isFrozen = false;

    // Stop capture if still running
    if (_captureReceivePort != null) {
      _captureReceivePort?.close();
      _captureReceivePort = null;
    }
    if (_captureIsolate != null) {
      _captureIsolate?.kill(priority: Isolate.immediate);
      _captureIsolate = null;
    }

    // Stop inference
    if (_inferenceSubscription != null) {
      _inferenceSubscription?.cancel();
      _inferenceSubscription = null;
    }

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
