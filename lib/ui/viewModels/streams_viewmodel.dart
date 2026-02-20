import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:uuid/uuid.dart';

/// ViewModel for the Streams screen.
///
/// Owns stream add/remove and form validation.
class StreamsViewModel extends ChangeNotifier {
  final AppService _appService;

  StreamsViewModel(this._appService) {
    _appService.streams.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _appService.streams.removeListener(notifyListeners);
    super.dispose();
  }

  List<StreamConfig> get streams => _appService.streams.all;

  /// Add a new RTSP stream. Returns true on success.
  Future<bool> addStream(String name, String url) async {
    if (name.trim().isEmpty || url.trim().isEmpty) return false;

    final newStream = StreamConfig(
      id: const Uuid().v4(),
      url: url.trim(),
      name: name.trim(),
    );

    await _appService.streams.add(newStream);
    notifyListeners();
    return true;
  }

  /// Remove a stream by ID.
  Future<void> removeStream(String streamId) async {
    await _appService.streams.remove(streamId);
    notifyListeners();
  }
}
