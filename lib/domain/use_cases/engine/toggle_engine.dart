import 'package:smart_store_linux/services/app_service.dart';

/// Toggles the inference engine on or off.
class ToggleEngine {
  final AppService _appService;

  ToggleEngine(this._appService);

  Future<void> call() => _appService.toggleEngine();
}
