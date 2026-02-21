import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/features/rendering/rendering_orchestrator.dart';
import 'package:smart_store_linux/features/rendering/sync/stream_sync_manager.dart';
import 'package:smart_store_linux/features/engine/engine_orchestrator.dart';

/// Widget-lifetime controller for managing the playback of a single video stream.
///
/// Tracks FPS, texture ID, and frame sync state, driving widget rebuilds via
/// [ChangeNotifier]. Belongs in the UI layer — not core — because its lifecycle
/// is tied to the widget tree.
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

  /// Stream of frame timestamps from RenderingManager
  Stream<int> get frameStream =>
      RenderingOrchestrator.instance.getFrameStream(streamId);

  /// Initialize the controller and underlying texture resources
  Future<void> initialize(int width, int height) async {
    if (_isInitialized) return;

    try {
      await _syncManager.initialize(width, height);
      _isInitialized = true;
      debugPrint(
        'StreamPlaybackController: Initialized for $streamId. TextureID: $textureId',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('StreamPlaybackController: Initialization error: $e');
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Called each widget frame tick for connection maintenance.
  int? onFrameTick() {
    final pipeline = EngineOrchestrator.instance.getPipeline(streamId);
    if (pipeline != null && pipeline.nativeVideoId > 0) {
      _syncManager.maintainConnection(pipeline.nativeVideoId);
      if (_syncManager.updateTextureFromProcessor(pipeline.textureId)) {
        notifyListeners();
      }
    }
    return textureId;
  }

  /// Request a specific frame be displayed. Returns true if rendered.
  Future<bool> showFrame(int timestamp) async {
    if (_isDisposed) return false;

    final rendered = await _syncManager.showFrame(
      timestamp,
      onShowFrame: (ts) async {
        final pipeline = EngineOrchestrator.instance.getPipeline(streamId);
        if (pipeline != null) {
          return await RenderingOrchestrator.instance.showFrame(
            pipeline.nativeVideoId,
            ts,
          );
        }
        return false;
      },
    );

    if (rendered) _updateStats();
    return rendered;
  }

  void _updateStats() {
    _frameCount++;
    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      _fps = _frameCount.toDouble();
      _frameCount = 0;
      _lastFpsUpdate = now;
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
