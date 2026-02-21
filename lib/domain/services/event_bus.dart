/// Abstract contract for the application event bus.
///
/// Decouples event producers (plugins, system) from consumers (BLoCs, UI).
abstract class EventBus {
  /// Stream of all application events.
  Stream<dynamic> get eventStream;

  /// Emit a new event to all listeners.
  void emit(dynamic event);

  /// Dispose resources.
  void dispose();
}
