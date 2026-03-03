import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/entities/config/plugin_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/use_cases/plugins/update_plugin.dart';
import 'plugins_event.dart';
import 'plugins_state.dart';

class PluginsBloc extends Bloc<PluginsEvent, PluginsState> {
  final UpdatePlugin _updatePlugin;
  final IConfigRepository _repo;

  PluginsBloc({
    required UpdatePlugin updatePlugin,
    required IConfigRepository repo,
  }) : _updatePlugin = updatePlugin,
       _repo = repo,
       super(const PluginsState()) {
    on<PluginsLoaded>(_onLoaded);
    on<PluginModelSet>(_onPluginModelSet);
  }

  Future<void> _onLoaded(PluginsLoaded event, Emitter<PluginsState> emit) async {
    emit(
      state.copyWith(
        plugins: kAvailablePlugins,
        availableModels: _repo.currentConfig.models,
      ),
    );

    await emit.forEach<AppConfig>(
      _repo.configStream,
      onData: (cfg) => state.copyWith(
        plugins: kAvailablePlugins,
        availableModels: cfg.models,
      ),
      onError: (_, _) => state,
    );
  }

  Future<void> _onPluginModelSet(
    PluginModelSet event,
    Emitter<PluginsState> emit,
  ) async {
    PluginConfig? plugin =
        _repo.getPlugin(event.pluginId) ??
        PluginConfig(id: event.pluginId, enabled: true);

    if (event.modelPath != null) {
      try {
        final model = _repo.currentConfig.models.firstWhere(
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
        debugPrint('PluginsBloc: Could not find model for ${event.modelPath}: $e');
      }
    } else {
      await _updatePlugin(plugin.copyWith(clearAssignedModel: true));
    }
  }

  /// Returns the resolved model file path for a given plugin, or null if none assigned.
  String? getModelPathForPlugin(String pluginId) {
    return _repo.getModelPathForPlugin(pluginId);
  }
}
