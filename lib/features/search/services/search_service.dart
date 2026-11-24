import '../../../data/models/calendar_event.dart';
import '../../../data/models/category.dart';
import '../../../data/models/task.dart';
import '../../calendar/services/recurrence_engine.dart';

class SearchResults {
  const SearchResults({this.events = const [], this.tasks = const []});
  final List<EventOccurrence> events;
  final List<Task> tasks;

  bool get isEmpty => events.isEmpty && tasks.isEmpty;
}

/// In-memory search over events and tasks.
class SearchService {
  const SearchService._();

  /// Matches every word of [query] (case-insensitive) against titles,
  /// descriptions, notes, locations and category names.
  ///
  /// A recurring event appears once, as its next occurrence on or after
  /// [now] (or its first occurrence if the series has ended).
  static SearchResults search({
    required String query,
    required Iterable<CalendarEvent> events,
    required Iterable<Task> tasks,
    required Map<String, Category> categories,
    required DateTime now,
  }) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const SearchResults();

    bool matches(List<String> fields) {
      final haystack = fields.join('\n').toLowerCase();
      return words.every(haystack.contains);
    }

    final foundEvents = <EventOccurrence>[];
    for (final e in events) {
      if (!matches([
        e.title,
        e.description,
        e.notes,
        e.location,
        categories[e.categoryId]?.name ?? '',
      ])) {
        continue;
      }
      final next = RecurrenceEngine.upcoming(e, now);
      foundEvents.add(next.isNotEmpty
          ? next.first
          : EventOccurrence(
              event: e,
              start: e.start,
              end: RecurrenceEngine.endFor(e, e.start),
            ));
    }
    // Upcoming first (soonest at the top), then past (most recent first).
    foundEvents.sort((a, b) {
      final aPast = a.end.isBefore(now), bPast = b.end.isBefore(now);
      if (aPast != bPast) return aPast ? 1 : -1;
      return aPast ? b.start.compareTo(a.start) : a.start.compareTo(b.start);
    });

    final foundTasks = [
      for (final t in tasks)
        if (matches([
          t.title,
          t.description,
          categories[t.categoryId]?.name ?? '',
        ]))
          t,
    ];
    return SearchResults(events: foundEvents, tasks: foundTasks);
  }
}
