import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/config/models/plugin_config.dart';
import 'package:smart_store_linux/domain/use_cases/plugins/update_plugin.dart';
import 'plugins_event.dart';
import 'plugins_state.dart';

class PluginsBloc extends Bloc<PluginsEvent, PluginsState> {
  final UpdatePlugin _updatePlugin;
  final ConfigService _configService;

  PluginsBloc({
    required UpdatePlugin updatePlugin,
    required ConfigService configService,
  }) : _updatePlugin = updatePlugin,
       _configService = configService,
       super(const PluginsState()) {
    on<PluginsLoaded>(_onLoaded);
    on<PluginModelSet>(_onPluginModelSet);

    _configService.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    add(const PluginsLoaded());
  }

  void _onLoaded(PluginsLoaded event, Emitter<PluginsState> emit) {
    emit(
      state.copyWith(
        plugins: _configService.availablePlugins,
        availableModels: _configService.models,
      ),
    );
  }

  Future<void> _onPluginModelSet(
    PluginModelSet event,
    Emitter<PluginsState> emit,
  ) async {
    PluginConfig? plugin =
        _configService.getPlugin(event.pluginId) ??
        PluginConfig(id: event.pluginId, enabled: true);

    if (event.modelPath != null) {
      try {
        final model = _configService.models.firstWhere(
          (m) => m.path == event.modelPath,
        );
        var updatedPlugin = plugin.copyWith(assignedModelId: model.id);

        // Apply default parameters based on plugin type
        final newParams = Map<String, dynamic>.from(updatedPlugin.parameters);
        if (event.pluginId == 'people_counting') {
          newParams['personClassId'] = 0;
          newParams['confidenceThreshold'] = 0.5;
        } else if (event.pluginId == 'kitchen_supervision') {
          newParams['handClassId'] = 4;
          newParams['confidenceThreshold'] = 0.5;
        }
        updatedPlugin = updatedPlugin.copyWith(parameters: newParams);
        await _updatePlugin(updatedPlugin);
      } catch (e) {
        debugPrint(
          'PluginsBloc: Could not find model for ${event.modelPath}: $e',
        );
      }
    } else {
      await _updatePlugin(plugin.copyWith(clearAssignedModel: true));
    }

    emit(
      state.copyWith(
        plugins: _configService.availablePlugins,
        availableModels: _configService.models,
      ),
    );
  }

  /// Returns the resolved model file path for a given plugin, or null if none assigned.
  String? getModelPathForPlugin(String pluginId) {
    return _configService.getModelPathForPlugin(pluginId);
  }

  @override
  Future<void> close() {
    _configService.removeListener(_onConfigChanged);
    return super.close();
  }
}
