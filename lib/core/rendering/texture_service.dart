import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service for managing native GPU textures on Linux
class TextureService {
  static const MethodChannel _channel = MethodChannel('native_onnx/texture');

  /// Create a new texture for video rendering
  /// Returns a map with 'textureId' and 'textureManagerId'
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
      debugPrint('[TextureService] Failed to create texture: $e');
      return null;
    }
  }

  /// Mark a texture as needing a frame update
  Future<void> updateTexture(int textureId) async {
    try {
      await _channel.invokeMethod('updateTexture', {'textureId': textureId});
    } catch (e) {
      debugPrint('[TextureService] Failed to update texture: $e');
    }
  }

  /// Connect a video stream to a texture for automatic updates
  Future<void> connectStreamToTexture(int videoId, int textureManagerId) async {
    try {
      await _channel.invokeMethod('connectStreamToTexture', {
        'videoId': videoId,
        'textureManagerId': textureManagerId,
      });
      debugPrint(
        '[TextureService] Connected video $videoId to texture $textureManagerId',
      );
    } catch (e) {
      debugPrint('[TextureService] Failed to connect stream: $e');
    }
  }
}
