import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/models/frames.dart';
import 'package:smart_store_linux/models/rtsp_stream.dart';
import 'package:smart_store_linux/services/inference_service.dart';
import 'package:smart_store_linux/stream_processing/capture_isolate.dart';
import 'package:smart_store_linux/stream_processing/isolate_params.dart';

/// Headless stream processor that manages video capture, inference, and display queues
///
/// Architecture:
/// - Capture: Runs in isolate, decodes video frames
/// - InferenceQueue (max 2): Buffers raw frames for inference
/// - DisplayQueue (max 10): Buffers processed frames with detections
/// - Display: Outputs frames for UI rendering
class HeadlessStreamProcessor {
  final RTSPStream stream;
  final String modelPath;
  int _nativeVideoId = 0;
  bool _isActive = true;

  // Freeze mode - stop inference but keep displaying raw frames
  bool _isFrozen = false;

  // Queue Configuration - Design Spec Limits
  static const int INFERENCE_QUEUE_MAX_SIZE = 2; // Buffer for incoming frames
  static const int DISPLAY_QUEUE_MAX_SIZE = 10; // Buffer for processed frames

  // InferenceQueue: Buffers raw frames from capture (max 2)
  // Purpose: Maintain smooth playback even if inference is slower than capture
  final Queue<RawFrame> _inferenceQueue = Queue<RawFrame>();

  // DisplayQueue: Buffers processed frames with detections (max 10)
  // Purpose: Sequential display with frame dropping if inference is too fast
  final Queue<ProcessedFrame> _displayQueue = Queue<ProcessedFrame>();

  final StreamController<ProcessedFrame> _frameStreamController =
      StreamController<ProcessedFrame>.broadcast();

  Stream<ProcessedFrame> get frameStream => _frameStreamController.stream;
  bool get isInitialized => _nativeVideoId > 0;
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

  HeadlessStreamProcessor({required this.stream, required this.modelPath});

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

            if (inferredFrame != null) {
              // Create ProcessedFrame with matching frame and detections
              final processedFrame = ProcessedFrame(
                imageBytes: inferredFrame.bytes,
                width: inferredFrame.width,
                height: inferredFrame.height,
                detections: List.from(_lastDetections),
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
      _captureIsolate = await Isolate.spawn(
        captureLoop,
        IsolateInitParams(stream.url, _captureReceivePort!.sendPort),
      );

      _captureReceivePort!.listen((message) {
        if (message is RawFrame) {
          // Add to InferenceQueue (max size 2)
          // Always keep the latest frames, drop oldest if full
          if (_inferenceQueue.length >= INFERENCE_QUEUE_MAX_SIZE) {
            _inferenceQueue.removeFirst(); // Drop oldest
          }
          _inferenceQueue.add(message);
        } else if (message is int) {
          _nativeVideoId = message;
        } else {
          debugPrint("Main: Received unknown message from isolate: $message");
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

          // Process every frame with backpressure control
          // Higher backpressure limit allows better GPU utilization with batching
          if (_pendingInferenceCount < 6) {
            final requestId = _requestIdCounter++;
            _pendingInferenceCount++;

            // Store the frame we're sending for inference
            _pendingFrames[requestId] = frame;

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

  /// Display loop: Sequentially display frames from DisplayQueue or InferenceQueue
  /// When frozen (stopped): Display raw frames from InferenceQueue (no inference)
  /// When running: Display ONLY processed frames from DisplayQueue (with matching detections)
  void _startDisplayLoop() async {
    while (_isActive) {
      try {
        ProcessedFrame? frameToDisplay;

        // When FROZEN (engine stopped): Show raw frames from InferenceQueue
        if (_isFrozen && _inferenceQueue.isNotEmpty) {
          final rawFrame = _inferenceQueue.first;
          frameToDisplay = ProcessedFrame(
            imageBytes: rawFrame.bytes,
            width: rawFrame.width,
            height: rawFrame.height,
            detections: [], // No detections when stopped
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
        }
      } catch (e) {
        debugPrint("SPM: Error in display loop: $e");
      }

      // Target ~60 FPS display for smoother playback
      await Future.delayed(const Duration(milliseconds: 16));
    }
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
            final processedFrame = ProcessedFrame(
              imageBytes: latestFrame.bytes,
              width: latestFrame.width,
              height: latestFrame.height,
              detections: List.from(_lastDetections),
            );

            if (_displayQueue.length >= DISPLAY_QUEUE_MAX_SIZE) {
              _displayQueue.removeFirst();
            }
            _displayQueue.add(processedFrame);
          }
        });

    debugPrint("Processor unfrozen for ${stream.id} - inference restarted");
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
