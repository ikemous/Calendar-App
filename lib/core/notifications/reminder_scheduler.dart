import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/events/providers/events_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../features/tasks/providers/tasks_provider.dart';
import '../home_widgets/countdown_widgets.dart';
import '../services/app_services.dart';
import 'lock_screen_planner.dart';
import 'notification_service.dart';
import 'reminder_planner.dart';

/// Keeps the OS notification schedule, and the countdown widgets, in step
/// with the stored data.
class ReminderScheduler {
  ReminderScheduler(this._ref);
  final Ref _ref;

  Future<void> _queue = Future.value();

  /// Replaces every pending notification with the current plan. Calls are
  /// queued so overlapping syncs cannot interleave.
  Future<void> sync() {
    _queue = _queue.then((_) => _run()).catchError((Object e) {
      // Never let a notification failure break saving data. Only the error
      // type is logged: reminder text is private.
      debugPrint('Reminder sync failed: ${e.runtimeType}');
    });
    return _queue;
  }

  Future<void> _run() async {
    final service = _ref.read(notificationServiceProvider);
    final native = _ref.read(countdownWidgetServiceProvider);
    final events = _ref.read(eventsProvider);
    final settings = _ref.read(settingsProvider);
    final now = _ref.read(clockProvider)();
    try {
      final plan = ReminderPlanner.plan(
        events: events,
        tasks: _ref.read(tasksProvider),
        settings: settings,
        now: now,
      );
      // Where the platform draws the lock screen itself (Android), the app
      // posts no cards of its own and leaves that notification alone.
      final nativeId = native.lockScreenNotificationId;
      final cards = nativeId != null
          ? const <LockScreenCard>[]
          : LockScreenPlanner.plan(events: events, settings: settings, now: now);
      await service.cancelAll(keep: {
        ?nativeId,
        for (final card in cards)
          if (card.showAt == null) card.id,
      });
      for (final reminder in plan) {
        await service.schedule(reminder);
      }
      // Posted last to first, so the featured card ends up on top.
      for (final card in cards.reversed) {
        await service.showCard(card, now: now);
      }
    } finally {
      // On its own, so a reminder failure cannot hold up the lock screen.
      try {
        await native.update(
          CountdownPlanner.plan(events: events, settings: settings, now: now),
          lockScreen: settings.notificationsEnabled,
          showNext: settings.showNextEventOnLockScreen,
          imagePath: settings.lockScreenImagePath,
        );
      } catch (e) {
        debugPrint('Lock screen update failed: ${e.runtimeType}');
      }
    }
  }
}

final reminderSchedulerProvider =
    Provider<ReminderScheduler>((ref) => ReminderScheduler(ref));
