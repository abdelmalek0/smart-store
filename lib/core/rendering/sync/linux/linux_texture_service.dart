import 'dart:developer';
import 'package:flutter/services.dart';

/// Linux-specific service for managing native GPU textures.
///
/// Wraps MethodChannel calls to the `native_onnx/texture` channel.
/// Co-located with [LinuxStreamSyncManager] which is its only caller.
class LinuxTextureService {
  static const MethodChannel _channel = MethodChannel('native_onnx/texture');

  /// Create a new texture for video rendering.
  /// Returns a map with `'textureId'` and `'textureManagerId'`, or null on failure.
  Future<Map<String, int>?> createVideoTexture(int width, int height) async {
    try {
      final result = await _channel.invokeMethod('createVideoTexture', {
        'width': width,
        'height': height,
      });
      if (result is Map) {
        return {
          'textureId': result['textureId'] as int,
          'textureManagerId': result['textureManagerId'] as int,
        };
      }
      return null;
    } catch (e) {
      log('[LinuxTextureService] Failed to create texture: $e');
      return null;
    }
  }

  /// Signal Flutter that a texture needs a frame update.
  Future<void> updateTexture(int textureId) async {
    try {
      await _channel.invokeMethod('updateTexture', {'textureId': textureId});
    } catch (e) {
      log('[LinuxTextureService] Failed to update texture: $e');
    }
  }

  /// Connect a native video stream to a texture for automatic frame delivery.
  Future<void> connectStreamToTexture(int videoId, int textureManagerId) async {
    try {
      await _channel.invokeMethod('connectStreamToTexture', {
        'videoId': videoId,
        'textureManagerId': textureManagerId,
      });
      log(
        '[LinuxTextureService] Connected video $videoId to texture mgr $textureManagerId',
      );
    } catch (e) {
      log('[LinuxTextureService] Failed to connect stream: $e');
    }
  }

  /// Dispose a texture and release native resources.
  Future<void> disposeTexture(int textureId, int textureManagerId) async {
    try {
      await _channel.invokeMethod('disposeTexture', {
        'textureId': textureId,
        'textureManagerId': textureManagerId,
      });
      log(
        '[LinuxTextureService] Disposed T$textureId (Mgr: $textureManagerId)',
      );
    } catch (e) {
      log('[LinuxTextureService] Failed to dispose texture: $e');
    }
  }
}
