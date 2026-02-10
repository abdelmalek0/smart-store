import 'package:smart_store_linux/backend/streaming/pipeline/stream_processor.dart';
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
  bool updateTextureFromProcessor(StreamProcessor processor) {
    if (_textureId == null && processor.textureId != null) {
      _textureId = processor.textureId;
      return true; // State changed
    }
    return false;
  }

  @override
  Future<void> maintainConnection(StreamProcessor processor) async {
    // No-op on Android. Connection is handled natively.
  }

  @override
  Future<bool> showFrame(StreamProcessor processor, int timestamp) async {
    if (_textureId != null) {
      final success = await processor.showFrame(timestamp);
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
