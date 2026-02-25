import 'package:smart_store_linux/domain/entities/config/app_config.dart';

/// Interface for platform-specific persistence implementations.
abstract class PersistenceRepository {
  /// Save the full application configuration.
  Future<void> saveConfig(AppConfig config);

  /// Load the full application configuration.
  Future<AppConfig?> loadConfig();
}
