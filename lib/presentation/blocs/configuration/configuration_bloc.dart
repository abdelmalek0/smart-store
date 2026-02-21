import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/domain/use_cases/configuration/set_active_plugin.dart';
import 'configuration_event.dart';
import 'configuration_state.dart';

class ConfigurationBloc extends Bloc<ConfigurationEvent, ConfigurationState> {
  final SetActivePlugin _setActivePlugin;
  final ConfigService _configService;

  ConfigurationBloc({
    required SetActivePlugin setActivePlugin,
    required ConfigService configService,
  }) : _setActivePlugin = setActivePlugin,
       _configService = configService,
       super(const ConfigurationState()) {
    on<ConfigurationLoaded>(_onLoaded);
    on<ConfigurationPluginSet>(_onPluginSet);

    _configService.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    add(const ConfigurationLoaded());
  }

  void _onLoaded(ConfigurationLoaded event, Emitter<ConfigurationState> emit) {
    emit(
      state.copyWith(
        streams: _configService.streams,
        plugins: _configService.availablePlugins,
      ),
    );
  }

  Future<void> _onPluginSet(
    ConfigurationPluginSet event,
    Emitter<ConfigurationState> emit,
  ) async {
    await _setActivePlugin(event.streamId, event.pluginId);
    emit(state.copyWith(streams: _configService.streams));
  }

  @override
  Future<void> close() {
    _configService.removeListener(_onConfigChanged);
    return super.close();
  }
}
