import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

class PluginsState extends Equatable {
  final List<PluginEntity> plugins;
  final List<ModelConfig> availableModels;

  const PluginsState({
    this.plugins = const [],
    this.availableModels = const [],
  });

  PluginsState copyWith({
    List<PluginEntity>? plugins,
    List<ModelConfig>? availableModels,
  }) {
    return PluginsState(
      plugins: plugins ?? this.plugins,
      availableModels: availableModels ?? this.availableModels,
    );
  }

  @override
  List<Object?> get props => [plugins, availableModels];
}
