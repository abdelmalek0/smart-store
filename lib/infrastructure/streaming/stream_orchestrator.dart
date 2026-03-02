import 'package:smart_store_linux/domain/entities/raw_frame.dart';
import 'dart:async';
import 'dart:developer';
import 'package:smart_store_linux/domain/entities/processed_frame.dart';
import 'package:smart_store_linux/infrastructure/streaming/capture_runtime.dart';
import 'package:smart_store_linux/infrastructure/streaming/stream_registry.dart';

import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/application/config/config_service.dart';

/// Per-stream slot for the frame-drop gate.
///
/// Ensures the pipeline always processes the **latest** available frame.
/// When [busy] is true (pipeline is processing), incoming frames overwrite
/// [pendingFrame] rather than being queued. When the pipeline calls
/// [StreamOrchestrator.releaseSlot], the pending frame (if any) is forwarded.
class _StreamSlot {
  bool busy = false;
  RawFrame? pendingFrame;

  // ── FPS / drop diagnostics ──────────────────────────────────
  int _captureFrames = 0;   // total frames received from isolate port
  int _droppedFrames = 0;   // frames TRULY dropped (pending slot overwritten)
  int _pipelineFrames = 0;  // frames actually dispatched to pipeline
  int _windowStartMs = DateTime.now().millisecondsSinceEpoch;
  static const int _logIntervalMs = 5000;

  // Source FPS tracking using generationTimeMs from the capture isolate.
  // Measures the real capture cadence, not the port-message processing rate.
  int _lastGenerationMs = 0;
  double _avgIntervalMs = 0.0;

  /// Call every time a frame arrives at the gate.
  /// [trulyDropped] = true ONLY when an existing pendingFrame is overwritten.
  /// [generationTimeMs] = timestamp set by the capture isolate when the frame
  ///                      was sent, used to compute real source FPS.
  void onFrameArrived({required bool trulyDropped, required int generationTimeMs}) {
    _captureFrames++;
    if (trulyDropped) _droppedFrames++;

    // Update source-FPS estimate using exponential moving average of intervals.
    if (_lastGenerationMs > 0 && generationTimeMs > _lastGenerationMs) {
      final interval = (generationTimeMs - _lastGenerationMs).toDouble();
      _avgIntervalMs = _avgIntervalMs == 0.0
          ? interval
          : _avgIntervalMs * 0.85 + interval * 0.15;
    }
    _lastGenerationMs = generationTimeMs;

    _maybeLog();
  }

  void onFrameDispatched() {
    _pipelineFrames++;
  }

  void _maybeLog() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - _windowStartMs;
    if (elapsedMs < _logIntervalMs) return;

    final elapsedSec = elapsedMs / 1000.0;
    // Source FPS: derived from capture-isolate generation timestamps (true capture rate).
    final sourceFps = _avgIntervalMs > 0
        ? (1000.0 / _avgIntervalMs).toStringAsFixed(1)
        : '?';
    // Gate arrival FPS: wall-clock rate of port-message processing (can be skewed by queuing).
    final gateFps   = (_captureFrames  / elapsedSec).toStringAsFixed(1);
    final pipeFps   = (_pipelineFrames / elapsedSec).toStringAsFixed(1);
    final dropPct   = _captureFrames > 0
        ? ((_droppedFrames / _captureFrames) * 100).toStringAsFixed(0)
        : '0';

    // ignore: avoid_print
    print('[Gate] source: $sourceFps fps (gate: $gateFps fps) | '
          'truly dropped: $_droppedFrames ($dropPct%) | '
          'pipeline: $pipeFps fps');

    // Reset window (keep avgIntervalMs — it's a rolling average, not a window count)
    _captureFrames  = 0;
    _droppedFrames  = 0;
    _pipelineFrames = 0;
    _windowStartMs  = now;
  }
}

/// Active Orchestrator for Stream Capture and Routing.
///
/// Responsibilities:
/// - Manages lifecycle of [CaptureRuntime] instances.
/// - Acts as the frame bus, routing frames to [PluginManager].
/// - Provides frame stream for Pipelines.
class StreamOrchestrator {
  static final StreamOrchestrator _instance = StreamOrchestrator._internal();
  factory StreamOrchestrator() => _instance;
  static StreamOrchestrator get instance => _instance;
  StreamOrchestrator._internal();

  // Frame Streams: Map<StreamId, StreamController<RawFrame>>
  // Kept here as per user request
  final Map<String, StreamController<RawFrame>> _frameControllers = {};
  final Map<String, StreamController<ProcessedFrame>>
  _processedFrameControllers = {};
  final Map<String, Map<int, String>> _streamLabels = {};
  final Map<String, StreamController<Map<int, String>>> _labelControllers = {};

  /// Per-stream frame-drop gate slots.
  final Map<String, _StreamSlot> _slots = {};

  /// Initialize all streams from configuration
  Future<void> initialize(List<StreamConfig> configs) async {
    for (final config in configs) {
      if (config.enabled) {
        await initializeStream(config);
      }
    }
  }

  /// Initialize and start a single stream
  Future<void> initializeStream(StreamConfig config) async {
    if (StreamRegistry.instance.isRegistered(config.id)) {
      log('StreamManager: Stream ${config.id} already initialized.');
      return;
    }

    log('StreamManager: Initializing stream ${config.id}...');

    final frameController = StreamController<RawFrame>.broadcast();
    _frameControllers[config.id] = frameController;

    final labelController = StreamController<Map<int, String>>.broadcast();
    _labelControllers[config.id] = labelController;

    final processedFrameController =
        StreamController<ProcessedFrame>.broadcast();
    _processedFrameControllers[config.id] = processedFrameController;

    // Create the gate slot for this stream
    final slot = _StreamSlot();
    _slots[config.id] = slot;

    final runtime = CaptureRuntime(
      streamUrl: config.url,
      streamId: config.id,
      onFrameReceived: (frame) {
        // Frame-drop gate: always keep the latest frame.
        // If the pipeline is busy, store as pending (overwrites any previous pending).
        // If free, forward immediately and mark the slot as busy.
        //
        // Drop counting: a frame is TRULY dropped only when it overwrites an
        // existing pendingFrame (i.e., that pending frame will never be dispatched).
        // Frames that sit in pending and get forwarded by releaseSlot are NOT dropped.
        final hadPending = slot.busy && slot.pendingFrame != null;
        slot.pendingFrame = frame;
        slot.onFrameArrived(
          trulyDropped: hadPending,
          generationTimeMs: frame.generationTimeMs,
        );
        if (!slot.busy && !frameController.isClosed) {
          slot.busy = true;
          final toSend = slot.pendingFrame!;
          slot.pendingFrame = null;
          slot.onFrameDispatched();
          frameController.add(toSend);
        }
      },
      onProcessedFrameReceived: (processed) {
        // Feed the processed frame controller - Pipeline will subscribe to this
        if (!processedFrameController.isClosed) {
          processedFrameController.add(processed);
        }
      },
      onLabelsReceived: (labels) {
        // Store labels for this stream so Pipeline can access them
        _streamLabels[config.id] = labels;
        _labelControllers[config.id]?.add(labels);
        log('StreamManager: Received ${labels.length} labels for ${config.id}');
      },
      onInitComplete: (vid, tex) {
        log('StreamManager: Stream ${config.id} initialized (VideoID: $vid)');
      },
    );

    // Register with StreamRegistry
    StreamRegistry.instance.register(runtime);

    log('StreamManager: Starting capture for ${config.id}');

    await runtime.start();
  }

  /// Get the frame stream for a given stream ID
  Stream<RawFrame>? getFrameStream(String streamId) {
    return _frameControllers[streamId]?.stream;
  }

  /// Get the label stream for a given stream ID
  Stream<Map<int, String>>? getLabelStream(String streamId) {
    return _labelControllers[streamId]?.stream;
  }

  /// Get the processed frame stream (Optimized Path) for a given stream ID
  Stream<ProcessedFrame>? getProcessedFrameStream(String streamId) {
    return _processedFrameControllers[streamId]?.stream;
  }

  /// Get current labels for a given stream ID
  Map<int, String>? getCurrentLabels(String streamId) {
    return _streamLabels[streamId];
  }

  /// Inject dynamic labels directly (e.g., from InferenceWorker)
  void updateLabels(String streamId, Map<int, String> labels) {
    if (labels.isNotEmpty) {
      _streamLabels[streamId] = labels;
      _labelControllers[streamId]?.add(labels);
      log('StreamManager: Updated ${labels.length} dynamic labels for $streamId from Inference');
    }
  }

  /// Get the native video ID for a stream (if active)
  int getNativeVideoId(String streamId) {
    return StreamRegistry.instance.get(streamId)?.nativeVideoId ?? 0;
  }

  /// Get the texture ID for a stream (if available)
  int? getTextureId(String streamId) {
    return StreamRegistry.instance.get(streamId)?.textureId;
  }

  /// Get the texture manager ID for a stream (if available)
  int? getTextureManagerId(String streamId) {
    return StreamRegistry.instance.get(streamId)?.textureManagerId;
  }

  /// Called by [Pipeline] when it finishes processing a frame.
  ///
  /// Releases the gate slot. If a newer frame arrived while the pipeline was
  /// busy, it is forwarded immediately; otherwise the slot is marked free.
  void releaseSlot(String streamId) {
    final slot = _slots[streamId];
    if (slot == null) return;
    final controller = _frameControllers[streamId];
    final pending = slot.pendingFrame;
    if (pending != null && controller != null && !controller.isClosed) {
      slot.pendingFrame = null;
      slot.onFrameDispatched(); // count this dispatch for FPS log
      // slot stays busy — we are dispatching another frame right now
      controller.add(pending);
    } else {
      slot.busy = false;
    }
  }

  /// Dispose a specific stream
  Future<void> disposeStream(String streamId) async {
    _slots.remove(streamId);

    final runtime = StreamRegistry.instance.get(streamId);
    if (runtime != null) {
      await runtime.dispose();
      StreamRegistry.instance.unregister(streamId);
    }
    await _frameControllers[streamId]?.close();
    _frameControllers.remove(streamId);

    await _labelControllers[streamId]?.close();
    _labelControllers.remove(streamId);

    await _processedFrameControllers[streamId]?.close();
    _processedFrameControllers.remove(streamId);

    _streamLabels.remove(streamId);
  }

  /// Dispose all streams
  Future<void> disposeAll() async {
    final runtimes = StreamRegistry.instance.runtimes;
    for (final runtime in runtimes) {
      await disposeStream(runtime.streamId);
    }
  }
}
