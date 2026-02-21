import 'package:equatable/equatable.dart';

abstract class ModelsEvent extends Equatable {
  const ModelsEvent();

  @override
  List<Object?> get props => [];
}

class ModelsLoaded extends ModelsEvent {
  const ModelsLoaded();
}

class ModelFileAdded extends ModelsEvent {
  final String path;

  const ModelFileAdded(this.path);

  @override
  List<Object?> get props => [path];
}

class ModelRemoved extends ModelsEvent {
  final String modelId;

  const ModelRemoved(this.modelId);

  @override
  List<Object?> get props => [modelId];
}

class ModelLabelsUpdated extends ModelsEvent {
  final String modelId;
  final Map<int, String> labels;

  const ModelLabelsUpdated({required this.modelId, required this.labels});

  @override
  List<Object?> get props => [modelId, labels];
}
