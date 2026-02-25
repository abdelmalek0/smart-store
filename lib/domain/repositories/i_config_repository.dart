import 'package:smart_store_linux/domain/entities/config/app_config.dart';

/// Abstract contract for application configuration persistence.
///
/// Decouples the domain layer from any specific storage mechanism
/// (file system, shared preferences, etc.).
abstract class IConfigRepository {
  /// Load the application configuration from the underlying store.
  Future<AppConfig> loadConfig();

  /// Persist the given [config] to the underlying store.
  Future<void> saveConfig(AppConfig config);
}
