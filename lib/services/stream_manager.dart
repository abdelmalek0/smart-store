import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/services/persistence_service.dart';

class StreamData {
  final String id;
  final String url;
  String? assignedModel;

  StreamData({required this.id, required this.url, this.assignedModel});

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'assignedModel': assignedModel,
  };

  factory StreamData.fromJson(Map<String, dynamic> json) {
    return StreamData(
      id: json['id'],
      url: json['url'],
      assignedModel: json['assignedModel'],
    );
  }
}

class StreamManager extends ChangeNotifier {
  final List<StreamData> _streams = [];
  final PersistenceService _persistence = PersistenceService();

  List<StreamData> get streams => List.unmodifiable(_streams);

  StreamManager() {
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    final data = await _persistence.loadConfig();
    if (data.containsKey('streams')) {
      final list = data['streams'] as List;
      _streams.clear();
      _streams.addAll(list.map((e) => StreamData.fromJson(e)));
      notifyListeners();
    }
  }

  Future<void> _saveStreams() async {
    final data = await _persistence.loadConfig();
    data['streams'] = _streams.map((e) => e.toJson()).toList();
    await _persistence.saveConfig(data);
  }

  void addStream(String id, String url) {
    _streams.add(StreamData(id: id, url: url));
    notifyListeners();
    _saveStreams();
  }

  void removeStream(String id) {
    _streams.removeWhere((element) => element.id == id);
    notifyListeners();
    _saveStreams();
  }

  void assignModel(String streamId, String? modelPath) {
    final index = _streams.indexWhere((element) => element.id == streamId);
    if (index != -1) {
      _streams[index].assignedModel = modelPath;
      notifyListeners();
      _saveStreams();
    }
  }

  String? getModelForStream(String streamId) {
    try {
      return _streams
          .firstWhere((element) => element.id == streamId)
          .assignedModel;
    } catch (_) {
      return null;
    }
  }
}
