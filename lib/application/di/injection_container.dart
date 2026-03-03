import 'package:get_it/get_it.dart';
import 'package:smart_store_linux/application/events/event_bus_impl.dart';
import 'package:smart_store_linux/application/services/app_service.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';

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

// Use Cases — Configuration
import 'package:smart_store_linux/domain/use_cases/configuration/set_active_plugin.dart';

// BLoCs
import 'package:smart_store_linux/application/blocs/dashboard/dashboard_bloc.dart';
import 'package:smart_store_linux/application/blocs/streams/streams_bloc.dart';
import 'package:smart_store_linux/application/blocs/models/models_bloc.dart';
import 'package:smart_store_linux/application/blocs/plugins/plugins_bloc.dart';
import 'package:smart_store_linux/application/blocs/configuration/configuration_bloc.dart';
import 'package:smart_store_linux/application/blocs/events_log/events_log_bloc.dart';
import 'package:smart_store_linux/application/blocs/playback/playback_bloc.dart';

/// Global service locator instance.
final sl = GetIt.instance;

/// Registers all dependencies into the [GetIt] service locator.
///
/// [repo] is the fully-initialised [IConfigRepository] (config already loaded).
void configureDependencies(IConfigRepository repo) {
  // ─────────────────────────────────────────────────────────────────────────
  // Core (singletons)
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<IConfigRepository>(() => repo);
  sl.registerLazySingleton<AppService>(() => AppService.instance);
  sl.registerLazySingleton<SystemService>(() => AppService.instance.system);
  sl.registerLazySingleton<EventBusImpl>(() => EventBusImpl.instance);

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Streams
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => GetStreams(repo));
  sl.registerLazySingleton(() => AddStream(repo));
  sl.registerLazySingleton(() => RemoveStream(repo));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Models
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => GetModels(repo));
  sl.registerLazySingleton(() => AddModel(repo));
  sl.registerLazySingleton(() => RemoveModel(repo));
  sl.registerLazySingleton(() => UpdateModel(repo));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Plugins
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => const GetPlugins());
  sl.registerLazySingleton(() => UpdatePlugin(repo));

  // ─────────────────────────────────────────────────────────────────────────
  // Use Cases — Configuration
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => SetActivePlugin(repo));

  // ─────────────────────────────────────────────────────────────────────────
  // BLoCs (factory: fresh instance per screen)
  // ─────────────────────────────────────────────────────────────────────────
  sl.registerFactory<DashboardBloc>(
    () => DashboardBloc(
      appService: sl<AppService>(),
      systemService: sl<SystemService>(),
      repo: repo,
    ),
  );

  sl.registerFactory<StreamsBloc>(
    () => StreamsBloc(
      addStream: sl<AddStream>(),
      removeStream: sl<RemoveStream>(),
      repo: repo,
    ),
  );

  sl.registerFactory<ModelsBloc>(
    () => ModelsBloc(
      addModel: sl<AddModel>(),
      removeModel: sl<RemoveModel>(),
      updateModel: sl<UpdateModel>(),
      repo: repo,
    ),
  );

  sl.registerFactory<PluginsBloc>(
    () => PluginsBloc(
      updatePlugin: sl<UpdatePlugin>(),
      repo: repo,
    ),
  );

  sl.registerFactory<ConfigurationBloc>(
    () => ConfigurationBloc(
      setActivePlugin: sl<SetActivePlugin>(),
      repo: repo,
    ),
  );

  sl.registerLazySingleton<EventsLogBloc>(
    () => EventsLogBloc(eventService: sl<EventBusImpl>()),
  );

  sl.registerFactory<PlaybackBloc>(() => PlaybackBloc());
}
