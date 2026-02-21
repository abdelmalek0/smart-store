import 'package:equatable/equatable.dart';

abstract class ConfigurationEvent extends Equatable {
  const ConfigurationEvent();

  @override
  List<Object?> get props => [];
}

class ConfigurationLoaded extends ConfigurationEvent {
  const ConfigurationLoaded();
}

class ConfigurationPluginSet extends ConfigurationEvent {
  final String streamId;
  final String? pluginId;

  const ConfigurationPluginSet({required this.streamId, this.pluginId});

  @override
  List<Object?> get props => [streamId, pluginId];
}
