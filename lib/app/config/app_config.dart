/// Static app-wide configuration.
class AppConfig {
  const AppConfig._();

  static const String appName = 'Yowchtech Calendar';

  /// Earliest and latest dates offered by date pickers.
  static final DateTime minDate = DateTime(1970);
  static final DateTime maxDate = DateTime(2100, 12, 31);
}
