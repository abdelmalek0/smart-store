import 'dart:io';
import 'package:smart_store_linux/core/engine/stream_pipeline.dart';

import 'linux/linux_stream_sync_manager.dart';
import 'android/android_stream_sync_manager.dart';

/// Abstract base class for platform-specific stream synchronization.
abstract class StreamSyncManager {
  final String streamId;

  StreamSyncManager(this.streamId);

  /// Factory constructor to return the correct platform implementation.
  factory StreamSyncManager.create(String streamId) {
    if (Platform.isLinux) {
      return LinuxStreamSyncManager(streamId);
    } else if (Platform.isAndroid) {
      return AndroidStreamSyncManager(streamId);
    }
    // Default/Fallback (could be CPU-only implementation, or reuse Linux/Android logic if appropriate)
    // For now, default to Linux as a "desktop" baseline or throw if unsupported
    return LinuxStreamSyncManager(streamId);
  }

  /// Get the current texture ID for rendering.
  int? get textureId;

  /// Initialize any platform-specific resources (e.g. create Linux texture).
  Future<void> initialize(int width, int height);

  /// Update state based on pipeline info (e.g. Android texture ID arriving late).
  /// Returns `true` if state changed.
  bool updateTextureFromProcessor(StreamPipeline processor);

  /// Maintain ongoing connection (e.g. Linux stream-to-texture binding).
  Future<void> maintainConnection(StreamPipeline processor);

  /// Strictly synchronize frame display.
  /// Returns `true` if frame should be rendered (or was rendered to texture).
  /// Returns `false` if frame dropped/missing in native buffer.
  Future<bool> showFrame(StreamPipeline processor, int timestamp);

  /// Dispose resources.
  void dispose();
}
