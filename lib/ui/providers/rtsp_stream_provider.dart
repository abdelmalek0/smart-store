import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:smart_store_linux/data/services/persistence_service.dart';
import 'package:smart_store_linux/core/streaming/models/rtsp_stream.dart';

class RTSPStreamProvider extends ChangeNotifier {
  final PersistenceService _persistence = PersistenceService();
  final List<RTSPStream> _streams = [];

  List<RTSPStream> get streams => _streams;

  RTSPStreamProvider() {
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    final List<dynamic>? streamList = await _persistence.loadKey('streams');
    if (streamList != null) {
        _streams.clear();
        for (var i in streamList) {
          try {
            _streams.add(RTSPStream.fromJson(i));
          } catch (e) {
             debugPrint("Error loading stream config: $e");
          }
        }
        notifyListeners();
    }
  }

  Future<void> _saveStreams() async {
    final List<Map<String, dynamic>> data = _streams.map((s) => s.toJson()).toList();
    await _persistence.saveKey('streams', data);
  }

  void addStream(String url, {String? name, String? modelPath, String? label}) {
    final id = const Uuid().v4();
    _streams.add(RTSPStream(
      id: id,
      url: url,
      name: name ?? 'Stream ${_streams.length + 1}',
      modelPath: modelPath,
      label: label,
    ));
    _saveStreams();
    notifyListeners();
  }

  void removeStream(String id) {
    _streams.removeWhere((s) => s.id == id);
    _saveStreams();
    notifyListeners();
  }

  // Update stream model association
  void updateStreamModel(String streamId, String? modelPath) {
    final index = _streams.indexWhere((s) => s.id == streamId);
    if (index != -1) {
      final stream = _streams[index];
      _streams[index] = RTSPStream(
        id: stream.id,
        url: stream.url,
        name: stream.name,
        modelPath: modelPath,
        label: stream.label,
      );
      _saveStreams();
      notifyListeners();
    }
  }
}
