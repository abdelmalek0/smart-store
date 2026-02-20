import 'dart:io';

import 'linux/linux_stream_sync_manager.dart';
import 'android/android_stream_sync_manager.dart';

/// Abstract base class for platform-specific stream synchronization.
abstract class StreamSyncManager {
  // Timestamp Synchronization
  int? _initialTimestamp;

  /// Corrects the incoming timestamp to match the native buffer's time base.
  int correctTimestamp(int timestamp) {
    if (_initialTimestamp == null) {
      _initialTimestamp = timestamp;
      // _initialSystemTime = DateTime.now().millisecondsSinceEpoch;
      // If the incoming timestamp is small (e.g. 0-based), but native is large (system time),
      // we might need to query native for its current time base or just rely on the first frame
      // to "snap" to.
      // However, if we receive 15000 and native has 52000, we need to add the diff.
      // But we don't know the native time yet until we try to show a frame and fail, or we query it.

      // Better approach: The timestamp we receive here *should* be the one coming from Native.
      // If Dart's Pipeline is preserving the Native timestamp, then it should match.
      // If DisplayQueue is generating its own, that's the bug.

      // Let's assume for now we just pass it through, but if we need offset, we add it here.
      return timestamp;
    }
    return timestamp;
  }

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
  bool updateTextureFromProcessor(int? textureId);

  /// Maintain ongoing connection (e.g. Linux stream-to-texture binding).
  Future<void> maintainConnection(int nativeVideoId);

  /// Strictly synchronize frame display.
  /// Returns `true` if frame should be rendered (or was rendered to texture).
  /// Returns `false` if frame dropped/missing in native buffer.
  Future<bool> showFrame(
    int timestamp, {
    required Future<bool> Function(int) onShowFrame,
  });

  /// Dispose resources.
  void dispose();
}
