class RTSPStream {
  final String id;
  final String url;
  final String name;
  final String? modelPath;
  final String? label;

  RTSPStream({
    required this.id,
    required this.url,
    required this.name,
    this.modelPath,
    this.label,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'name': name,
      'modelPath': modelPath,
      'label': label,
    };
  }

  factory RTSPStream.fromJson(Map<String, dynamic> json) {
    return RTSPStream(
      id: json['id'] as String,
      url: json['url'] as String,
      name: json['name'] as String,
      modelPath: json['modelPath'] as String?,
      label: json['label'] as String?,
    );
  }
}
