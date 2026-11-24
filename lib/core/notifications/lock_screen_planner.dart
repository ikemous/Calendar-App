import '../../data/models/app_settings.dart';
import '../../data/models/calendar_event.dart';
import '../../features/calendar/services/recurrence_engine.dart';
import '../utilities/date_utils.dart';
import '../utilities/formatters.dart';
import 'notification_service.dart';
import 'reminder_planner.dart';

/// Works out which events are pinned to the lock screen, and when.
///
/// The lock screen has two slots, each a silent, persistent notification:
///
/// * The **featured** event: one repeating event the user picked. Its
///   current or next occurrence is shown until that occurrence ends, when
///   the following occurrence takes its place.
/// * The **next event**: the next upcoming event other than the featured
///   one, shown until it starts, when the one after takes its place.
///
/// Because the app may be closed at those moments, the hand-overs are
/// scheduled with the OS in advance, like reminders.
class LockScreenPlanner {
  const LockScreenPlanner._();

  static const String nextLabel = 'Next';
  static const String featuredLabel = 'Featured';

  /// Length of the featured chain: the occurrence shown now plus the
  /// scheduled hand-overs to later occurrences.
  static const int maxFeatured = 4;

  /// Length of the next-event chain, counted the same way. Together with
  /// [maxFeatured] and [ReminderPlanner.maxScheduled] this stays within the
  /// 64 pending notifications iOS allows.
  static const int maxNext = 6;

  /// How far ahead the next event is looked for.
  static const Duration horizon = Duration(days: 30);

  /// The occurrence of [e] that is in progress or coming up at [now], or
  /// null if the event is over.
  static EventOccurrence? currentOccurrence(CalendarEvent e, DateTime now) =>
      notOver(e, now, 1).firstOrNull;

  /// Up to [limit] occurrences of [e] that are not over at [now].
  static List<EventOccurrence> notOver(
      CalendarEvent e, DateTime now, int limit) {
    final result = <EventOccurrence>[];
    final spanDays = daysBetween(e.start, e.end);
    final hint = addDays(dateOnly(now), -spanDays - 1);
    for (final s in RecurrenceEngine.starts(e, hint: hint)) {
      final o = EventOccurrence(
          event: e, start: s, end: RecurrenceEngine.endFor(e, s));
      if (!endOf(o).isAfter(now)) continue;
      result.add(o);
      if (result.length >= limit) break;
    }
    return result;
  }

  /// The event in the featured slot, if it still exists and repeats.
  static CalendarEvent? featuredEvent(
      Iterable<CalendarEvent> events, AppSettings settings) {
    final id = settings.featuredEventId;
    if (id == null) return null;
    for (final e in events) {
      if (e.id == id) return e.isRecurring ? e : null;
    }
    return null;
  }

  static List<LockScreenCard> plan({
    required Iterable<CalendarEvent> events,
    required AppSettings settings,
    required DateTime now,
  }) {
    if (!settings.notificationsEnabled) return const [];
    final result = <LockScreenCard>[];

    // The featured slot: this occurrence, then the ones after it.
    final featured = featuredEvent(events, settings);
    if (featured != null) {
      DateTime? showAt;
      for (final o in notOver(featured, now, maxFeatured)) {
        final hideAt = endOf(o);
        // Occurrences that overlap the previous one are skipped.
        if (showAt != null && !hideAt.isAfter(showAt)) continue;
        result.add(LockScreenCard(
          id: ReminderPlanner.stableId('lock|featured|${_key(o)}'),
          label: featuredLabel,
          title: _title(o),
          body: _body(o, settings, now),
          showAt: showAt,
          hideAt: hideAt,
          payload: NotificationTarget.event(o.event.id, o.start).encode(),
        ));
        showAt = hideAt;
      }
    }

    if (!settings.showNextEventOnLockScreen) return result;

    // The next-event slot. The featured event has its own slot, so it is
    // left out of this one.
    final until = now.add(horizon);
    final upcoming = <EventOccurrence>[];
    for (final e in events) {
      if (e.id == featured?.id) continue;
      for (final o in RecurrenceEngine.upcoming(e, now,
          limit: maxNext + 1, before: until)) {
        if (o.start.isAfter(now)) upcoming.add(o);
      }
    }
    upcoming.sort(RecurrenceEngine.compareOccurrences);

    // Events starting at the same moment share one card.
    final groups = <List<EventOccurrence>>[];
    for (final o in upcoming) {
      if (groups.isNotEmpty && groups.last.first.start == o.start) {
        groups.last.add(o);
      } else {
        groups.add([o]);
      }
    }

    DateTime? showAt;
    for (final group in groups.take(maxNext)) {
      final o = group.first;
      final more = group.length - 1;
      final body = _body(o, settings, now);
      result.add(LockScreenCard(
        id: ReminderPlanner.stableId('lock|next|${_key(o)}'),
        label: nextLabel,
        title: _title(o),
        body: more == 0 ? body : '$body · +$more more',
        showAt: showAt,
        hideAt: o.start,
        payload: NotificationTarget.event(o.event.id, o.start).encode(),
      ));
      showAt = o.start;
    }
    return result;
  }

  static String _key(EventOccurrence o) =>
      '${o.event.id}|${o.start.millisecondsSinceEpoch}';

  static String _title(EventOccurrence o) =>
      o.event.title.isEmpty ? 'Event' : o.event.title;

  /// The moment the occurrence is over.
  static DateTime endOf(EventOccurrence o) {
    if (o.allDay) return addDays(dateOnly(o.end), 1);
    return o.end.isAfter(o.start)
        ? o.end
        : o.start.add(const Duration(minutes: 1));
  }

  // Like reminders, the text leaves out descriptions and notes. The date is
  // absolute ("Mon, Nov 23", not "Today") because the card can stay on
  // screen past midnight.
  static String _body(EventOccurrence o, AppSettings settings, DateTime now) {
    final day = formatDayShort(o.start, now: now);
    final time = o.allDay
        ? '$day · All day'
        : '$day · ${formatTime(o.start, settings.use24Hour)}';
    final location = o.event.location.trim();
    return location.isEmpty ? time : '$time · $location';
  }
}
