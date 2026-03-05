import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';

class PluginsState extends Equatable {
  final List<PluginEntity> plugins;
  final List<ModelConfig> availableModels;
  final List<PluginConfig> pluginConfigs;

  const PluginsState({
    this.plugins = const [],
    this.availableModels = const [],
    this.pluginConfigs = const [],
  });

  PluginsState copyWith({
    List<PluginEntity>? plugins,
    List<ModelConfig>? availableModels,
    List<PluginConfig>? pluginConfigs,
  }) {
    return PluginsState(
      plugins: plugins ?? this.plugins,
      availableModels: availableModels ?? this.availableModels,
      pluginConfigs: pluginConfigs ?? this.pluginConfigs,
    );
  }

  @override
  List<Object?> get props => [plugins, availableModels, pluginConfigs];
}
