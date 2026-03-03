import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/config/app_config.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/domain/use_cases/configuration/set_active_plugin.dart';
import 'configuration_event.dart';
import 'configuration_state.dart';

class ConfigurationBloc extends Bloc<ConfigurationEvent, ConfigurationState> {
  final SetActivePlugin _setActivePlugin;
  final IConfigRepository _repo;

  ConfigurationBloc({
    required SetActivePlugin setActivePlugin,
    required IConfigRepository repo,
  }) : _setActivePlugin = setActivePlugin,
       _repo = repo,
       super(const ConfigurationState()) {
    on<ConfigurationLoaded>(_onLoaded);
    on<ConfigurationPluginSet>(_onPluginSet);
  }

  Future<void> _onLoaded(
    ConfigurationLoaded event,
    Emitter<ConfigurationState> emit,
  ) async {
    emit(
      state.copyWith(
        streams: _repo.currentConfig.streams,
        plugins: kAvailablePlugins,
      ),
    );

    await emit.forEach<AppConfig>(
      _repo.configStream,
      onData: (cfg) => state.copyWith(
        streams: cfg.streams,
        plugins: kAvailablePlugins,
      ),
      onError: (_, _) => state,
    );
  }

  Future<void> _onPluginSet(
    ConfigurationPluginSet event,
    Emitter<ConfigurationState> emit,
  ) async {
    await _setActivePlugin(event.streamId, event.pluginId);
    // configStream fires after mutation, so emit.forEach above updates state
  }
}
