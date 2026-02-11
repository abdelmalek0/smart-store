import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/streaming/models/rtsp_stream.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';

/// ViewModel for the Streams screen.
///
/// Owns stream add/remove and form validation.
class StreamsViewModel extends ChangeNotifier {
  final RTSPStreamProvider streamProvider;

  StreamsViewModel({required this.streamProvider});

  List<RTSPStream> get streams => streamProvider.streams;

  /// Add a new RTSP stream. Returns true on success.
  bool addStream(String name, String url) {
    if (name.trim().isEmpty || url.trim().isEmpty) return false;
    streamProvider.addStream(url.trim(), name: name.trim());
    notifyListeners();
    return true;
  }

  /// Remove a stream by ID.
  void removeStream(String streamId) {
    streamProvider.removeStream(streamId);
    notifyListeners();
  }
}
