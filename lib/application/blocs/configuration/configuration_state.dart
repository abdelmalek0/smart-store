import 'package:equatable/equatable.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';

class ConfigurationState extends Equatable {
  final List<StreamConfig> streams;
  final List<PluginEntity> plugins;

  const ConfigurationState({this.streams = const [], this.plugins = const []});

  ConfigurationState copyWith({
    List<StreamConfig>? streams,
    List<PluginEntity>? plugins,
  }) {
    return ConfigurationState(
      streams: streams ?? this.streams,
      plugins: plugins ?? this.plugins,
    );
  }

  @override
  List<Object?> get props => [streams, plugins];
}
