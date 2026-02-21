import 'package:equatable/equatable.dart';

/// Domain entity representing an AI model.
///
/// Pure value object — no JSON annotations, no Flutter dependencies.
class ModelEntity extends Equatable {
  final String id;
  final String path;
  final String name;
  final Map<int, String> labels;

  const ModelEntity({
    required this.id,
    required this.path,
    required this.name,
    this.labels = const {},
  });

  ModelEntity copyWith({
    String? id,
    String? path,
    String? name,
    Map<int, String>? labels,
  }) {
    return ModelEntity(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      labels: labels ?? this.labels,
    );
  }

  @override
  List<Object?> get props => [id, path, name, labels];
}
