import '../../data/models/app_settings.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/task.dart';
import '../../features/calendar/services/recurrence_engine.dart';
import '../utilities/date_utils.dart';
import '../utilities/formatters.dart';
import 'notification_service.dart';

/// Works out which reminders should currently be scheduled with the OS.
///
/// The whole schedule is recomputed after every change, which makes
/// "reschedule on edit" and "cancel on delete" fall out naturally: a
/// reminder that is no longer in the plan is simply not scheduled again.
class ReminderPlanner {
  const ReminderPlanner._();

  /// iOS keeps at most 64 pending notifications per app, so only the
  /// soonest reminders are scheduled (the rest of the allowance belongs to
  /// `LockScreenPlanner`). The plan is refreshed on every launch and data
  /// change, which keeps the window rolling forward.
  static const int maxScheduled = 56;
  static const Duration horizon = Duration(days: 120);

  /// Clock hour all-day reminders are measured from.
  static const int allDayHour = 9;

  static List<ScheduledReminder> plan({
    required Iterable<CalendarEvent> events,
    required Iterable<Task> tasks,
    required AppSettings settings,
    required DateTime now,
  }) {
    if (!settings.notificationsEnabled) return const [];
    final until = now.add(horizon);
    final result = <ScheduledReminder>[];

    for (final e in events) {
      if (e.reminders.isEmpty) continue;
      final maxOffset = e.reminders.reduce((a, b) => a > b ? a : b);
      final occurrences = RecurrenceEngine.upcoming(
        e,
        dateOnly(now),
        // A little extra, because today's occurrences may already have
        // passed and get filtered out below.
        limit: maxScheduled + 2,
        before: until.add(Duration(minutes: maxOffset)),
      );
      for (final o in occurrences) {
        final base = e.allDay
            ? DateTime(o.start.year, o.start.month, o.start.day, allDayHour)
            : o.start;
        for (final minutes in e.reminders.toSet()) {
          final when = base.subtract(Duration(minutes: minutes));
          if (!when.isAfter(now) || when.isAfter(until)) continue;
          result.add(ScheduledReminder(
            id: stableId('e|${e.id}|${o.start.millisecondsSinceEpoch}|$minutes'),
            title: e.title.isEmpty ? 'Event' : e.title,
            body: _eventBody(o, settings),
            when: when,
            payload: NotificationTarget.event(e.id, o.start).encode(),
          ));
        }
      }
    }

    for (final t in tasks) {
      final due = t.dueMoment;
      final minutes = t.reminderMinutes;
      if (t.completed || due == null || minutes == null) continue;
      final when = due.subtract(Duration(minutes: minutes));
      if (!when.isAfter(now) || when.isAfter(until)) continue;
      result.add(ScheduledReminder(
        id: stableId('t|${t.id}|$minutes'),
        title: t.title.isEmpty ? 'Task' : t.title,
        body: t.hasDueTime
            ? 'Task due ${formatDayShort(due)} at ${formatTime(due, settings.use24Hour)}'
            : 'Task due ${formatDayShort(due)}',
        when: when,
        payload: NotificationTarget.task(t.id).encode(),
      ));
    }

    result.sort((a, b) => a.when.compareTo(b.when));
    return result.length > maxScheduled
        ? result.sublist(0, maxScheduled)
        : result;
  }

  // The body deliberately leaves out descriptions and notes: notification
  // text is visible on the lock screen.
  static String _eventBody(EventOccurrence o, AppSettings settings) {
    final time = o.allDay
        ? '${formatDayShort(o.start)} · All day'
        : '${formatDayShort(o.start)} · ${formatTime(o.start, settings.use24Hour)}';
    final location = o.event.location.trim();
    return location.isEmpty ? time : '$time · $location';
  }

  /// Deterministic positive 31-bit id (FNV-1a), stable across app restarts.
  static int stableId(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}
