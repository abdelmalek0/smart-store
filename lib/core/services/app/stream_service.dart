import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/config/models/stream_config.dart';
import 'package:smart_store_linux/core/controllers/stream_playback_controller.dart';

/// Service responsible for managing video streams.
class StreamService extends ChangeNotifier {
  StreamService() {
    // Listen to ConfigService changes to propagate updates if needed
    ConfigService.instance.addListener(notifyListeners);
  }

  List<StreamConfig> get all => ConfigService.instance.streams;

  Future<void> add(StreamConfig stream) async {
    await ConfigService.instance.addStream(stream);
    // ConfigService.notifyListeners() will trigger this service's listener
  }

  Future<void> remove(String streamId) async {
    await ConfigService.instance.removeStream(streamId);
  }

  /// Create a controller for managing playback of a specific stream
  StreamPlaybackController createPlaybackController(String streamId) {
    return StreamPlaybackController(streamId);
  }

  @override
  void dispose() {
    ConfigService.instance.removeListener(notifyListeners);
    super.dispose();
  }
}
