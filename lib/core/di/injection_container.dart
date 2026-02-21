import 'package:get_it/get_it.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/features/events/event_bus_impl.dart';
import 'package:smart_store_linux/services/app_service.dart';

// Use Cases — Streams
import 'package:smart_store_linux/domain/use_cases/streams/get_streams.dart';
import 'package:smart_store_linux/domain/use_cases/streams/add_stream.dart';
import 'package:smart_store_linux/domain/use_cases/streams/remove_stream.dart';

// Use Cases — Models
import 'package:smart_store_linux/domain/use_cases/models/get_models.dart';
import 'package:smart_store_linux/domain/use_cases/models/add_model.dart';
import 'package:smart_store_linux/domain/use_cases/models/remove_model.dart';
import 'package:smart_store_linux/domain/use_cases/models/update_model.dart';

// Use Cases — Plugins
import 'package:smart_store_linux/domain/use_cases/plugins/get_plugins.dart';
import 'package:smart_store_linux/domain/use_cases/plugins/update_plugin.dart';

// Use Cases — Engine
import 'package:smart_store_linux/domain/use_cases/engine/toggle_engine.dart';

// Use Cases — Configuration
import 'package:smart_store_linux/domain/use_cases/configuration/set_active_plugin.dart';

// BLoCs
import 'package:smart_store_linux/presentation/blocs/dashboard/dashboard_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/streams/streams_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/models/models_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/configuration/configuration_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/events_log/events_log_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/playback/playback_bloc.dart';

/// Global service locator instance.
final sl = GetIt.instance;

/// Registers all dependencies into the [GetIt] service locator.
///
/// Call this once at application startup before [runApp].
void configureDependencies() {
  // ─────────────────────────────────────────────────────────────────────────
  // Core Services (singletons kept by AppService internals, exposed via sl)
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<AppService>(() => AppService.instance);
  sl.registerLazySingleton<ConfigService>(() => ConfigService.instance);
  sl.registerLazySingleton<SystemService>(() => AppService.instance.system);
  sl.registerLazySingleton<EventBusImpl>(() => EventBusImpl.instance);

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Streams
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => GetStreams(sl<ConfigService>()));
  sl.registerLazySingleton(() => AddStream(sl<ConfigService>()));
  sl.registerLazySingleton(() => RemoveStream(sl<ConfigService>()));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Models
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => GetModels(sl<ConfigService>()));
  sl.registerLazySingleton(() => AddModel(sl<ConfigService>()));
  sl.registerLazySingleton(() => RemoveModel(sl<ConfigService>()));
  sl.registerLazySingleton(() => UpdateModel(sl<ConfigService>()));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Plugins
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => GetPlugins(sl<ConfigService>()));
  sl.registerLazySingleton(() => UpdatePlugin(sl<ConfigService>()));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Engine
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => ToggleEngine(sl<AppService>()));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Configuration
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => SetActivePlugin(sl<ConfigService>()));

  // ─────────────────────────────────────────────────────────────────────────
  // BLoCs  (factory: a fresh instance is created for each screen)
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerFactory<DashboardBloc>(
    () => DashboardBloc(
      toggleEngine: sl<ToggleEngine>(),
      appService: sl<AppService>(),
      systemService: sl<SystemService>(),
    ),
  );

  sl.registerFactory<StreamsBloc>(
    () => StreamsBloc(
      addStream: sl<AddStream>(),
      removeStream: sl<RemoveStream>(),
      configService: sl<ConfigService>(),
    ),
  );

  sl.registerFactory<ModelsBloc>(
    () => ModelsBloc(
      addModel: sl<AddModel>(),
      removeModel: sl<RemoveModel>(),
      updateModel: sl<UpdateModel>(),
      configService: sl<ConfigService>(),
    ),
  );

  sl.registerFactory<PluginsBloc>(
    () => PluginsBloc(
      updatePlugin: sl<UpdatePlugin>(),
      configService: sl<ConfigService>(),
    ),
  );

  sl.registerFactory<ConfigurationBloc>(
    () => ConfigurationBloc(
      setActivePlugin: sl<SetActivePlugin>(),
      configService: sl<ConfigService>(),
    ),
  );

  // EventsLogBloc is registered as a singleton-factory so all consumers
  // share the same event history for the lifetime of the app.
  sl.registerLazySingleton<EventsLogBloc>(
    () => EventsLogBloc(eventService: sl<EventBusImpl>()),
  );

  sl.registerFactory<PlaybackBloc>(() => PlaybackBloc());
}
