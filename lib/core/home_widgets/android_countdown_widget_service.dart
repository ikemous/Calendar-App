import 'package:flutter/services.dart';

import 'countdown_widgets.dart';

/// Talks to the native Android lock screen display (`CountdownWidgets.kt`).
class AndroidCountdownWidgetService implements CountdownWidgetService {
  static const _channel = MethodChannel('calendar_app/widgets');

  /// Must match `CountdownWidgets.NOTIFICATION_ID`.
  @override
  int? get lockScreenNotificationId => 7001;

  @override
  Future<void> update(
    CountdownData data, {
    required bool lockScreen,
    required bool showNext,
    String? imagePath,
  }) =>
      _channel.invokeMethod<void>('update', {
        'data': data.encode(),
        'lockScreen': lockScreen,
        'showNext': showNext,
        'image': imagePath,
      });
}
