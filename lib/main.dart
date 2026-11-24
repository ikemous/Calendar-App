import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/home_widgets/android_countdown_widget_service.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/reminder_scheduler.dart';
import 'core/services/app_services.dart';
import 'features/sync/providers/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load everything from the local database before the first frame.
  final bootstrap = await AppBootstrap.load();
  final notifications = _createNotificationService();

  final container = ProviderContainer(overrides: [
    bootstrapProvider.overrideWithValue(bootstrap),
    notificationServiceProvider.overrideWithValue(notifications),
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      countdownWidgetServiceProvider
          .overrideWithValue(AndroidCountdownWidgetService()),
  ]);

  void open(String? payload) {
    final target = NotificationTarget.decode(payload);
    if (target != null) container.read(routerProvider).push(target.route);
  }

  String? launchPayload;
  try {
    await notifications.init(onTap: open);
    launchPayload = await notifications.launchPayload();
  } catch (e) {
    // The calendar must still open if notifications are unavailable.
    debugPrint('Notification setup failed: ${e.runtimeType}');
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const CalendarApp(),
  ));

  // Refresh the rolling reminder window, and open the event if the app was
  // started by tapping a notification.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    container.read(reminderSchedulerProvider).sync();
    container.read(syncControllerProvider.notifier).syncNow();
    open(launchPayload);
  });

  // Coming back to the app: pick up changes made elsewhere and refresh the
  // rolling reminder window.
  AppLifecycleListener(onResume: () {
    container.read(reminderSchedulerProvider).sync();
    container.read(syncControllerProvider.notifier).syncNow();
  });
}

NotificationService _createNotificationService() {
  if (kIsWeb) return const NoopNotificationService();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => LocalNotificationService(),
    _ => const NoopNotificationService(),
  };
}
