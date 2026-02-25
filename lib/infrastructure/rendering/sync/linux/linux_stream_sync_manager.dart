import 'dart:developer';
import 'package:native_onnx/native_onnx.dart';
import 'linux_texture_service.dart';
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
      final textureResult = await LinuxTextureService().createVideoTexture(
        width,
        height,
      );
      if (textureResult != null) {
        _textureId = textureResult['textureId'];
        _textureManagerId = textureResult['textureManagerId'];
        log(
          '[LinuxStreamSyncManager] Initialized texture. ID: $_textureId, ManagerID: $_textureManagerId',
        );
      }
    } catch (e) {
      log('[LinuxStreamSyncManager] Texture creation error: $e');
    }
  }

  @override
  bool updateTextureFromProcessor(int? textureId) {
    // No-op for Linux usually, as we create texture explicitly.
    // Unless we change architecture to have processor create it.
    return false;
  }

  @override
  Future<void> maintainConnection(int nativeVideoId) async {
    if (!_isTextureConnected &&
        _textureManagerId != null &&
        nativeVideoId > 0) {
      try {
        await LinuxTextureService().connectStreamToTexture(
          nativeVideoId,
          _textureManagerId!,
        );
        _isTextureConnected = true;
        log(
          '[LinuxStreamSyncManager] Connected stream $nativeVideoId to texture mgr $_textureManagerId',
        );
      } catch (e) {
        log('[LinuxStreamSyncManager] Failed to connect stream: $e');
      }
    }
  }

  @override
  Future<bool> showFrame(
    int timestamp, {
    required Future<bool> Function(int) onShowFrame,
  }) async {
    if (_textureManagerId != null && _textureId != null) {
      // Direct call to NativeInferenceService using the correct Texture Manager ID.
      // We ignore the provided [onShowFrame] callback because it likely carries
      // the Native Video ID (from StreamManager) instead of the Texture Manager ID.
      // Using [onShowFrame] would cause an ID mismatch (e.g. VideoID 1 vs TextureID 0).

      final success = NativeInferenceService().showFrame(
        _textureManagerId!,
        timestamp,
      );

      if (!success) {
        log(
          '[LinuxStreamSyncManager] ❌ Frame $timestamp NOT FOUND in texture buffer (Mgr: $_textureManagerId)',
        );
        return false;
      }

      // Signal Flutter texture to update
      LinuxTextureService().updateTexture(_textureId!);
      return true;
    }
    // If not initialized, assume success to keep pipeline moving (limitless mode)
    return true;
  }

  @override
  void dispose() {
    if (_textureId != null && _textureManagerId != null) {
      LinuxTextureService().disposeTexture(_textureId!, _textureManagerId!);
    }
    _textureId = null;
    _textureManagerId = null;
    _isTextureConnected = false;
  }
}
