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
    // On Linux, the texture is created explicitly during initialization.
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
      // Use textureManagerId directly; the onShowFrame callback carries the
      // native VideoID which would cause an ID mismatch.
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
    // Not yet initialized — let the pipeline continue.
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
