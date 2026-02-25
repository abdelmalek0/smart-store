enum EventSeverity {
  info,
  warning,
  critical;

  factory EventSeverity.fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'warning':
        return EventSeverity.warning;
      case 'critical':
        return EventSeverity.critical;
      case 'info':
      default:
        return EventSeverity.info;
    }
  }

  String get label => name.toUpperCase();
}
