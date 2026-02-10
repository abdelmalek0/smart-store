/// Tracks stream statistics: FPS, decode time, inference time, etc.
class StreamStatsTracker {
  // Stats
  int _decodeMs = 0;
  int _inferenceMs = 0;
  int _postprocessMs = 0;
  double _fps = 0.0;

  // FPS calculation
  final List<int> _frameTimestamps = [];
  static const int fpsWindowSize = 10;

  // Getters
  int get decodeMs => _decodeMs;
  int get inferenceMs => _inferenceMs;
  int get postprocessMs => _postprocessMs;
  double get fps => _fps;

  /// Update timing stats from a frame
  void updateTiming(Map<String, int> timing) {
    _decodeMs = timing['decode'] ?? 0;
    _inferenceMs = timing['inference'] ?? 0;
    _postprocessMs = timing['postprocess'] ?? 0;
  }

  /// Register a new frame arrival for FPS calculation
  void onFrameDisplayed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _frameTimestamps.add(now);

    // Maintain window size
    if (_frameTimestamps.length > fpsWindowSize) {
      _frameTimestamps.removeAt(0);
    }

    // Calculate FPS
    if (_frameTimestamps.length >= 2) {
      final duration = _frameTimestamps.last - _frameTimestamps.first;
      if (duration > 0) {
        _fps = ((_frameTimestamps.length - 1) * 1000) / duration;
      }
    }
  }

  void reset() {
    _frameTimestamps.clear();
    _fps = 0.0;
    _decodeMs = 0;
    _inferenceMs = 0;
    _postprocessMs = 0;
  }
}
