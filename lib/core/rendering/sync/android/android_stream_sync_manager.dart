import '../stream_sync_manager.dart';

/// Android implementation of StreamSyncManager
/// Handles adoption of texture ID from processor and strict sync.
class AndroidStreamSyncManager extends StreamSyncManager {
  AndroidStreamSyncManager(super.streamId);

  int? _textureId;

  @override
  int? get textureId => _textureId;

  @override
  Future<void> initialize(int width, int height) async {
    // No-op on Android. Texture is created by the native plugin/processor.
  }

  @override
  bool updateTextureFromProcessor(int? textureId) {
    if (_textureId == null && textureId != null) {
      _textureId = textureId;
      return true; // State changed
    }
    return false;
  }

  @override
  Future<void> maintainConnection(int nativeVideoId) async {
    // No-op on Android. Connection is handled natively.
  }

  @override
  Future<bool> showFrame(
    int timestamp, {
    required Future<bool> Function(int) onShowFrame,
  }) async {
    if (_textureId != null) {
      final success = await onShowFrame(timestamp);
      return success;
    }
    // If no texture yet, return true to allow fallback or waiting
    return true;
  }

  @override
  void dispose() {
    _textureId = null;
  }
}
