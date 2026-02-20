import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/rendering/sync/stream_sync_manager.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/engine/pipeline_manager.dart';

/// Controller for managing the playback of a specific video stream.
///
/// Encapsulates synchronization, connection maintenance, and state management.
class StreamPlaybackController extends ChangeNotifier {
  final String streamId;
  final StreamSyncManager _syncManager;

  // State
  bool _isInitialized = false;
  bool _isDisposed = false;
  Object? _error;

  // Playback Stats
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  StreamPlaybackController(this.streamId)
    : _syncManager = StreamSyncManager.create(streamId);

  bool get isInitialized => _isInitialized;
  Object? get error => _error;
  double get fps => _fps;

  /// The texture ID for rendering (nullable until initialized)
  int? get textureId => _syncManager.textureId;

  /// Stream of frames from the pipeline
  Stream<int> get frameStream {
    // Use RenderingManager directly to get persistent stream, bypassing Pipeline race condition
    return AppService.instance.engine.rendering.getFrameStream(streamId);
  }

  /// Initialize the controller and underlying resources
  Future<void> initialize(int width, int height) async {
    if (_isInitialized) return;

    try {
      await _syncManager.initialize(width, height);
      _isInitialized = true;
      debugPrint(
        "StreamPlaybackController: Initialized for $streamId. TextureID: $textureId",
      );
      notifyListeners();
    } catch (e) {
      debugPrint("StreamPlaybackController: Initialization error: $e");
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Called when the widget frame loop Ticks.
  /// Returns existing texture ID if ready to render.
  int? onFrameTick() {
    // Check connection maintenance
    final pipeline = PipelineManager.instance.getPipeline(streamId);
    if (pipeline != null && pipeline.nativeVideoId > 0) {
      _syncManager.maintainConnection(pipeline.nativeVideoId);

      // Update texture if processor changed it (Android)
      if (_syncManager.updateTextureFromProcessor(pipeline.textureId)) {
        notifyListeners(); // Texture changed, rebuild UI
      }
    }
    return textureId;
  }

  /// Render a frame for the given timestamp.
  /// Returns true if frame was rendered, false otherwise.
  Future<bool> showFrame(int timestamp) async {
    if (_isDisposed) return false;

    final rendered = await _syncManager.showFrame(
      timestamp,
      onShowFrame: (ts) async {
        final pipeline = PipelineManager.instance.getPipeline(streamId);
        if (pipeline != null) {
          // debugPrint("StreamPlaybackController: Requesting showFrame for vid=${pipeline.nativeVideoId} ts=$ts");
          return await AppService.instance.engine.rendering.showFrame(
            pipeline.nativeVideoId,
            ts,
          );
        }
        return false;
      },
    );

    if (rendered) {
      // debugPrint("StreamPlaybackController: Frame $timestamp rendered (Texture $textureId)");
      _updateStats();
    }

    return rendered;
  }

  void _updateStats() {
    _frameCount++;
    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      _fps = _frameCount.toDouble();
      _frameCount = 0;
      _lastFpsUpdate = now;
      // Notify less frequently to avoid UI spam?
      // Or bind to a ValueNotifier for stats if performance is an issue.
      // For now, simple notify.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _syncManager.dispose();
    super.dispose();
  }
}
