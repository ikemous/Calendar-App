import 'dart:math' as math;

import '../../../core/utilities/date_utils.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/recurrence_rule.dart';

/// Expands events (recurring or not) into concrete occurrences.
///
/// All arithmetic is done on local wall-clock dates, so a 9:00 weekly event
/// stays at 9:00 across daylight-saving changes.
class RecurrenceEngine {
  const RecurrenceEngine._();

  /// Safety stop for rules that never end.
  static const int _maxYear = 2500;

  static int _key(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute).millisecondsSinceEpoch;

  /// End of the occurrence that starts at [start].
  static DateTime endFor(CalendarEvent e, DateTime start) {
    final spanDays = daysBetween(e.start, e.end);
    return e.allDay
        ? addDays(dateOnly(start), spanDays)
        : DateTime(start.year, start.month, start.day + spanDays, e.end.hour,
            e.end.minute);
  }

  /// Occurrence starts in ascending order, honouring `until`, `count` and
  /// excluded dates. [hint] lets open-ended rules skip straight to the
  /// neighbourhood of a date instead of iterating from the first occurrence.
  static Iterable<DateTime> starts(CalendarEvent e, {DateTime? hint}) sync* {
    final rule = e.recurrence;
    if (rule == null) {
      yield e.start;
      return;
    }
    final excluded = {for (final d in e.exDates) _key(d)};
    var produced = 0;
    for (final d in _raw(e, rule, rule.count == null ? hint : null)) {
      if (rule.count != null && produced >= rule.count!) return;
      produced++;
      if (excluded.contains(_key(d))) continue;
      yield d;
    }
  }

  static Iterable<DateTime> _raw(
      CalendarEvent e, RecurrenceRule rule, DateTime? hint) sync* {
    final s = e.start;
    final step = rule.interval;
    final u = rule.until;
    final untilEnd = u == null ? null : DateTime(u.year, u.month, u.day, 23, 59, 59);
    bool past(DateTime d) =>
        d.year > _maxYear || (untilEnd != null && d.isAfter(untilEnd));

    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        var n = hint == null ? 0 : math.max(0, daysBetween(s, hint) ~/ step - 1);
        for (;; n++) {
          final d = DateTime(s.year, s.month, s.day + n * step, s.hour, s.minute);
          if (past(d)) return;
          yield d;
        }
      case RecurrenceFrequency.weekly:
        final days = rule.weekdays.isEmpty
            ? [s.weekday]
            : (rule.weekdays.toList()..sort());
        final week0 = addDays(dateOnly(s), -(s.weekday - 1));
        var n = hint == null
            ? 0
            : math.max(0, daysBetween(week0, hint) ~/ (7 * step) - 1);
        for (;; n++) {
          for (final wd in days) {
            final d = DateTime(week0.year, week0.month,
                week0.day + n * 7 * step + (wd - 1), s.hour, s.minute);
            if (d.isBefore(s)) continue;
            if (past(d)) return;
            yield d;
          }
        }
      case RecurrenceFrequency.monthly:
        var n = hint == null
            ? 0
            : math.max(
                0,
                ((hint.year - s.year) * 12 + hint.month - s.month) ~/ step - 1);
        for (;; n++) {
          final total = s.month - 1 + n * step;
          final y = s.year + total ~/ 12;
          final m = total % 12 + 1;
          if (past(DateTime(y, m, 1))) return;
          final int day;
          if (rule.weekOrdinal != null && rule.weekdays.isNotEmpty) {
            // "The nth weekday of the month" (or the last one).
            final found =
                nthWeekdayOfMonth(y, m, rule.weekdays.first, rule.weekOrdinal!);
            if (found == null) continue;
            day = found;
          } else {
            // Months without this day (e.g. the 31st) are skipped.
            if (s.day > daysInMonth(y, m)) continue;
            day = s.day;
          }
          final d = DateTime(y, m, day, s.hour, s.minute);
          if (d.isBefore(s)) continue;
          if (past(d)) return;
          yield d;
        }
      case RecurrenceFrequency.yearly:
        var n = hint == null ? 0 : math.max(0, (hint.year - s.year) ~/ step - 1);
        for (;; n++) {
          final y = s.year + n * step;
          if (past(DateTime(y, 1, 1))) return;
          // 29 February only occurs in leap years.
          if (s.day > daysInMonth(y, s.month)) continue;
          final d = DateTime(y, s.month, s.day, s.hour, s.minute);
          if (past(d)) return;
          yield d;
        }
    }
  }

  /// Day of the month of the [ordinal]th [weekday] (1-4, or -1 for the last)
  /// in the given month, or null if the month has no such day.
  static int? nthWeekdayOfMonth(int year, int month, int weekday, int ordinal) {
    final days = daysInMonth(year, month);
    if (ordinal < 0) {
      final lastWeekday = DateTime(year, month, days).weekday;
      final day = days - (lastWeekday - weekday + 7) % 7 + (ordinal + 1) * 7;
      return day >= 1 ? day : null;
    }
    final firstWeekday = DateTime(year, month, 1).weekday;
    final day = 1 + (weekday - firstWeekday + 7) % 7 + (ordinal - 1) * 7;
    return day <= days ? day : null;
  }

  /// Occurrences of [e] that overlap the half-open range `[from, to)`.
  static List<EventOccurrence> expand(
      CalendarEvent e, DateTime from, DateTime to) {
    final result = <EventOccurrence>[];
    final spanDays = daysBetween(e.start, e.end);
    final hint = addDays(dateOnly(from), -spanDays - 1);
    for (final s in starts(e, hint: hint)) {
      if (!s.isBefore(to)) break;
      final end = endFor(e, s);
      final endExclusive = e.allDay
          ? addDays(end, 1)
          : (end.isAfter(s) ? end : s.add(const Duration(minutes: 1)));
      if (endExclusive.isAfter(from)) {
        result.add(EventOccurrence(event: e, start: s, end: end));
      }
    }
    return result;
  }

  /// All occurrences of [events] overlapping `[from, to)`, sorted by start.
  static List<EventOccurrence> occurrencesInRange(
      Iterable<CalendarEvent> events, DateTime from, DateTime to) {
    final result = <EventOccurrence>[
      for (final e in events) ...expand(e, from, to),
    ];
    result.sort(compareOccurrences);
    return result;
  }

  /// All-day first, then by start time, then by title.
  static int compareOccurrences(EventOccurrence a, EventOccurrence b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.event.title.toLowerCase().compareTo(b.event.title.toLowerCase());
  }

  /// Occurrences covering the calendar day [day].
  static List<EventOccurrence> forDay(
      Iterable<EventOccurrence> occurrences, DateTime day) {
    final list = occurrences.where((o) => o.coversDay(day)).toList();
    list.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return compareOccurrences(a, b);
    });
    return list;
  }

  /// Up to [limit] occurrences starting at or after [after].
  static List<EventOccurrence> upcoming(CalendarEvent e, DateTime after,
      {int limit = 1, DateTime? before}) {
    final result = <EventOccurrence>[];
    for (final s in starts(e, hint: after)) {
      if (before != null && !s.isBefore(before)) break;
      if (s.isBefore(after)) continue;
      result.add(EventOccurrence(event: e, start: s, end: endFor(e, s)));
      if (result.length >= limit) break;
    }
    return result;
  }

  /// Number of occurrences the rule produces before [start] (excluded dates
  /// still count, as they do for `count`).
  static int countBefore(CalendarEvent e, DateTime start) {
    final rule = e.recurrence;
    if (rule == null) return 0;
    var n = 0;
    for (final d in _raw(e, rule, null)) {
      if (!d.isBefore(start)) break;
      if (rule.count != null && n >= rule.count!) break;
      n++;
    }
    return n;
  }
}
