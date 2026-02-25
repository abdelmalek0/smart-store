import 'package:equatable/equatable.dart';

abstract class PluginsEvent extends Equatable {
  const PluginsEvent();

  @override
  List<Object?> get props => [];
}

class PluginsLoaded extends PluginsEvent {
  const PluginsLoaded();
}

class PluginModelSet extends PluginsEvent {
  final String pluginId;
  final String? modelPath;

  const PluginModelSet({required this.pluginId, this.modelPath});

  @override
  List<Object?> get props => [pluginId, modelPath];
}
