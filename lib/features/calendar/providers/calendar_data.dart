import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utilities/date_utils.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/task.dart';
import '../../events/providers/events_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../services/recurrence_engine.dart';

/// Dated tasks that should appear inside calendar views, honouring the
/// "show tasks" and "show completed tasks" settings.
final calendarTasksProvider = Provider<List<Task>>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.showTasksInCalendar) return const [];
  return [
    for (final t in ref.watch(tasksProvider))
      if (t.dueDate != null && (settings.showCompletedTasks || !t.completed)) t,
  ]..sort(compareTasks);
});

/// Events and tasks for a span of days, indexed by day for fast lookup.
class CalendarRange {
  CalendarRange({
    required this.from,
    required this.to,
    required Iterable<CalendarEvent> events,
    required Iterable<Task> tasks,
  }) {
    final occurrences = RecurrenceEngine.occurrencesInRange(events, from, to);
    for (final o in occurrences) {
      var day = o.firstDay.isBefore(from) ? from : o.firstDay;
      while (!day.isAfter(o.lastDay) && day.isBefore(to)) {
        (_occurrences[_key(day)] ??= []).add(o);
        day = addDays(day, 1);
      }
    }
    for (final list in _occurrences.values) {
      list.sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return RecurrenceEngine.compareOccurrences(a, b);
      });
    }
    for (final t in tasks) {
      final due = t.dueDate;
      if (due == null || due.isBefore(from) || !due.isBefore(to)) continue;
      (_tasks[_key(due)] ??= []).add(t);
    }
  }

  /// Inclusive start and exclusive end, both local midnights.
  final DateTime from;
  final DateTime to;
  final Map<int, List<EventOccurrence>> _occurrences = {};
  final Map<int, List<Task>> _tasks = {};

  static int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  List<EventOccurrence> occurrencesOn(DateTime day) =>
      _occurrences[_key(day)] ?? const [];

  List<Task> tasksOn(DateTime day) => _tasks[_key(day)] ?? const [];

  bool hasItems(DateTime day) =>
      _occurrences.containsKey(_key(day)) || _tasks.containsKey(_key(day));

  bool get isEmpty => _occurrences.isEmpty && _tasks.isEmpty;
}

/// Builds a [CalendarRange] from current data. Rebuilds (in the calling
/// widget) whenever events, tasks or the relevant settings change.
CalendarRange watchRange(WidgetRef ref, DateTime from, DateTime to) =>
    CalendarRange(
      from: dateOnly(from),
      to: dateOnly(to),
      events: ref.watch(eventsProvider),
      tasks: ref.watch(calendarTasksProvider),
    );
