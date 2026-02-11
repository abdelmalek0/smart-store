import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/streaming/models/rtsp_stream.dart';

/// ViewModel for the Playback / Live Monitoring screen.
///
/// Owns selected stream state and sidebar toggle.
class PlaybackViewModel extends ChangeNotifier {
  String? _selectedStreamId;
  bool _isSidebarOpen = true;

  String? get selectedStreamId => _selectedStreamId;
  bool get isSidebarOpen => _isSidebarOpen;

  /// Select a stream for playback.
  void selectStream(String streamId) {
    if (_selectedStreamId != streamId) {
      _selectedStreamId = streamId;
      notifyListeners();
    }
  }

  /// Auto-select first stream if none selected.
  void autoSelectFirst(List<RTSPStream> streams) {
    if (_selectedStreamId == null && streams.isNotEmpty) {
      _selectedStreamId = streams.first.id;
      // Don't notify — this is called from build; caller handles rebuild.
    }
  }

  /// Toggle sidebar visibility.
  void toggleSidebar() {
    _isSidebarOpen = !_isSidebarOpen;
    notifyListeners();
  }
}
