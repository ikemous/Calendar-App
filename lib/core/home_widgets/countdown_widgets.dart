import 'dart:convert';

import '../../data/models/app_settings.dart';
import '../../data/models/calendar_event.dart';
import '../../features/calendar/services/recurrence_engine.dart';
import '../notifications/lock_screen_planner.dart';
import '../utilities/date_utils.dart';

/// One line a countdown widget can show: "[title]   12 days".
class CountdownEntry {
  const CountdownEntry({
    required this.title,
    required this.start,
    required this.until,
  });

  final String title;

  /// The day counted down to.
  final DateTime start;

  /// The entry is shown until this moment, then the next one takes over.
  final DateTime until;

  Map<String, Object> toJson() => {
        'title': title,
        'startMs': start.millisecondsSinceEpoch,
        'untilMs': until.millisecondsSinceEpoch,
      };
}

/// What the two widgets show, now and later. Each list is in the order the
/// entries take over from one another. The widget itself picks the first
/// entry that is still current and works out the day count, so it stays
/// right while the app is closed.
class CountdownData {
  const CountdownData({required this.featured, required this.next});

  /// Occurrences of the featured repeating event (an anniversary, say).
  final List<CountdownEntry> featured;

  /// The upcoming events, other than the featured one.
  final List<CountdownEntry> next;

  String encode() => jsonEncode({
        'featured': [for (final e in featured) e.toJson()],
        'next': [for (final e in next) e.toJson()],
      });
}

class CountdownPlanner {
  const CountdownPlanner._();

  static const int maxFeatured = 12;
  static const int maxNext = 40;

  /// How far ahead the next event is looked for.
  static const Duration horizon = Duration(days: 366);

  static CountdownData plan({
    required Iterable<CalendarEvent> events,
    required AppSettings settings,
    required DateTime now,
  }) {
    final featured = LockScreenPlanner.featuredEvent(events, settings);
    final featuredEntries = <CountdownEntry>[
      if (featured != null)
        for (final o
            in LockScreenPlanner.notOver(featured, now, maxFeatured))
          _entry(o, LockScreenPlanner.endOf(o)),
    ];

    final until = now.add(horizon);
    final upcoming = <EventOccurrence>[];
    for (final e in events) {
      if (e.id == featured?.id) continue;
      if (e.allDay) {
        // An all-day event counts as "next" for the whole of its day.
        for (final o in LockScreenPlanner.notOver(e, now, 10)) {
          if (o.start.isBefore(until)) upcoming.add(o);
        }
      } else {
        for (final o
            in RecurrenceEngine.upcoming(e, now, limit: 10, before: until)) {
          if (o.start.isAfter(now)) upcoming.add(o);
        }
      }
    }
    upcoming.sort(RecurrenceEngine.compareOccurrences);

    return CountdownData(
      featured: featuredEntries,
      next: [
        for (final o in upcoming.take(maxNext))
          _entry(o, o.allDay ? LockScreenPlanner.endOf(o) : o.start),
      ],
    );
  }

  static CountdownEntry _entry(EventOccurrence o, DateTime until) =>
      CountdownEntry(
        title: o.event.title.isEmpty ? 'Event' : o.event.title,
        start: o.start,
        until: until,
      );

  /// The entry a widget shows at [now], or null when there is none.
  static CountdownEntry? current(List<CountdownEntry> entries, DateTime now) {
    for (final e in entries) {
      if (e.until.isAfter(now)) return e;
    }
    return null;
  }

  /// "Today", "1 day" or "12 days". The native widget uses the same rule.
  static String daysLabel(CountdownEntry entry, DateTime now) {
    final days = daysBetween(now, entry.start);
    if (days <= 0) return 'Today';
    return days == 1 ? '1 day' : '$days days';
  }
}

/// Hands countdown data to the platform, which draws it on the lock screen.
abstract interface class CountdownWidgetService {
  /// Id of the lock screen notification the platform draws itself, or null
  /// when it draws none and the app should post its own notification cards.
  int? get lockScreenNotificationId;

  /// [lockScreen]: whether anything may be shown on the lock screen.
  /// [showNext]: whether the next-event countdown is wanted.
  /// [imagePath]: the user's picture for the featured event, if any.
  Future<void> update(
    CountdownData data, {
    required bool lockScreen,
    required bool showNext,
    String? imagePath,
  });
}

/// Used where there is no native lock screen display (iOS for now, tests).
class NoopCountdownWidgetService implements CountdownWidgetService {
  const NoopCountdownWidgetService();

  @override
  int? get lockScreenNotificationId => null;

  @override
  Future<void> update(
    CountdownData data, {
    required bool lockScreen,
    required bool showNext,
    String? imagePath,
  }) async {}
}
