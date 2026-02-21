import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/core/config/models/model_config.dart';

enum ModelsStatus { initial, loading, success, failure }

class ModelsState extends Equatable {
  final ModelsStatus status;
  final List<ModelConfig> models;
  final String? errorMessage;

  const ModelsState({
    this.status = ModelsStatus.initial,
    this.models = const [],
    this.errorMessage,
  });

  ModelsState copyWith({
    ModelsStatus? status,
    List<ModelConfig>? models,
    String? errorMessage,
  }) {
    return ModelsState(
      status: status ?? this.status,
      models: models ?? this.models,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, models, errorMessage];
}
