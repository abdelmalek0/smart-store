import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/rendering/texture_service.dart';
import 'package:smart_store_linux/core/streaming/services/ffmpeg_video_service.dart';
import 'package:smart_store_linux/core/engine/pipeline/stream_processor.dart';
import '../stream_sync_manager.dart';

/// Linux implementation of StreamSyncManager
/// Handles explicit texture creation and FFmpeg-Texture linkage.
class LinuxStreamSyncManager extends StreamSyncManager {
  LinuxStreamSyncManager(super.streamId);

  int? _textureId;
  int? _textureManagerId;
  bool _isTextureConnected = false;

  @override
  int? get textureId => _textureId;

  // Linux supports texture managing, Android doesn't need this exposed usually,
  // but we keep it internal or expose if strictly needed.
  // The base class doesn't strictly need to expose this getter if only used internally
  // by logic here, but StreamSyncManager definition might need it if DetachedStreamPlayer used it.
  // DetachedStreamPlayer only used .textureId.
  // We'll keep _textureManagerId internal here.

  @override
  Future<void> initialize(int width, int height) async {
    try {
      final textureResult = await TextureService().createVideoTexture(
        width,
        height,
      );
      if (textureResult != null) {
        _textureId = textureResult['textureId'];
        _textureManagerId = textureResult['textureManagerId'];
      }
    } catch (e) {
      debugPrint("[LinuxStreamSyncManager] Texture creation error: $e");
    }
  }

  @override
  bool updateTextureFromProcessor(StreamProcessor processor) {
    // No-op for Linux usually, as we create texture explicitly.
    // Unless we change architecture to have processor create it.
    return false;
  }

  @override
  Future<void> maintainConnection(StreamProcessor processor) async {
    if (!_isTextureConnected &&
        _textureManagerId != null &&
        processor.nativeVideoId > 0) {
      try {
        await TextureService().connectStreamToTexture(
          processor.nativeVideoId,
          _textureManagerId!,
        );
        _isTextureConnected = true;
        debugPrint("[LinuxStreamSyncManager] Connected stream to texture");
      } catch (e) {
        // Ignore temporary connection errors, retry next frame
      }
    }
  }

  @override
  Future<bool> showFrame(StreamProcessor processor, int timestamp) async {
    if (_textureManagerId != null && _textureId != null) {
      final success = await FFmpegVideoService.showFrame(
        _textureManagerId!,
        timestamp,
      );

      if (!success) return false;

      // Re-check referencing _textureId as it might have been disposed during async wait
      if (_textureId != null) {
        // Signal Flutter texture is ready
        TextureService().updateTexture(_textureId!);
        return true;
      }
      return false;
    }
    // If no texture logic active (e.g. CPU mode/Fallback), return true to proceed
    return true;
  }

  @override
  void dispose() {
    _textureId = null;
    _textureManagerId = null;
    _isTextureConnected = false;
  }
}
