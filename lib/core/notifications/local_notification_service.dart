import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';

/// [NotificationService] backed by `flutter_local_notifications`.
///
/// Reminders are handed to the OS scheduler (AlarmManager on Android,
/// UNUserNotificationCenter on iOS), so they fire while the app is in the
/// background or closed, and are restored after a reboot on Android.
class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _channelDescription = 'Event and task reminders';

  static const _lockChannelId = 'lock_screen';
  static const _lockChannelName = 'Lock screen events';
  static const _lockChannelDescription =
      'Keeps your next event and featured events on the lock screen';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init({required void Function(String payload) onTap}) async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Reminders are scheduled as absolute instants, so an unknown zone
      // name only affects how the plugin labels the time, not when it fires.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        // Permission is requested later, in context, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap(payload);
      },
    );
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  @override
  Future<bool> hasPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _android?.areNotificationsEnabled() ?? false;
    }
    final options = await _ios?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _android?.requestNotificationsPermission() ?? false;
    }
    return await _ios?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }

  // Exact delivery when the OS allows it; otherwise fall back to inexact
  // delivery rather than failing.
  Future<AndroidScheduleMode> _scheduleMode() async {
    final exact = defaultTargetPlatform != TargetPlatform.android ||
        (await _android?.canScheduleExactNotifications() ?? false);
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
      payload: reminder.payload,
      androidScheduleMode: await _scheduleMode(),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> showCard(LockScreenCard card, {required DateTime now}) async {
    final showAt = card.showAt;
    final visibleFor = card.hideAt.difference(showAt ?? now);
    if (visibleFor <= Duration.zero) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _lockChannelId,
        _lockChannelName,
        channelDescription: _lockChannelDescription,
        // Default importance keeps the card out of the "silent" group, which
        // many phones hide on the lock screen. It still makes no sound.
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        // Stays put until the event is over, then removes itself.
        ongoing: true,
        autoCancel: false,
        timeoutAfter: visibleFor.inMilliseconds,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.event,
        showWhen: false,
      ),
      // iOS has no persistent notifications: the card is an ordinary quiet
      // one that stays in the lock screen list until dismissed.
      iOS: DarwinNotificationDetails(
        subtitle: card.label,
        presentSound: false,
        presentBadge: false,
        interruptionLevel: InterruptionLevel.passive,
        threadIdentifier: _lockChannelId,
      ),
    );
    // Android bundles an app's notifications into one collapsed card that
    // shows only "title text" per line, so the slot name goes in the title.
    final title = defaultTargetPlatform == TargetPlatform.android
        ? '${card.label}: ${card.title}'
        : card.title;
    if (showAt == null) {
      await _plugin.show(
        id: card.id,
        title: title,
        body: card.body,
        payload: card.payload,
        notificationDetails: details,
      );
    } else {
      await _plugin.zonedSchedule(
        id: card.id,
        title: title,
        body: card.body,
        scheduledDate: tz.TZDateTime.from(showAt, tz.local),
        payload: card.payload,
        androidScheduleMode: await _scheduleMode(),
        notificationDetails: details,
      );
    }
  }

  @override
  Future<void> cancelAll({Set<int> keep = const {}}) async {
    if (keep.isEmpty) return _plugin.cancelAll();
    // Leave the kept cards on screen, so refreshing them does not make them
    // blink; everything else goes.
    await _plugin.cancelAllPendingNotifications();
    final List<ActiveNotification> active;
    try {
      active = await _plugin.getActiveNotifications();
    } catch (_) {
      return _plugin.cancelAll();
    }
    for (final n in active) {
      final id = n.id;
      if (id != null && !keep.contains(id)) await _plugin.cancel(id: id);
    }
  }
}
