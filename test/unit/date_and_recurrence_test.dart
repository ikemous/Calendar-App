import 'package:calendar_app/core/utilities/date_utils.dart';
import 'package:calendar_app/core/utilities/formatters.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/calendar/services/overlap_layout.dart';
import 'package:calendar_app/features/calendar/services/recurrence_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<DateTime> starts(CalendarEvent event, DateTime from, DateTime to) =>
    RecurrenceEngine.expand(event, from, to).map((o) => o.start).toList();

void main() {
  group('date calculations', () {
    test('daysBetween counts calendar days', () {
      expect(daysBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 1)), 1);
      expect(daysBetween(DateTime(2026, 3, 1), DateTime(2026, 2, 27)), -2);
      expect(daysBetween(DateTime(2024, 2, 28, 23), DateTime(2024, 3, 1, 1)), 2);
      // A whole year, across any daylight-saving changes.
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), 365);
    });

    test('addMonths clamps to the end of shorter months', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(addMonths(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
      expect(addMonths(DateTime(2026, 1, 15), -1), DateTime(2025, 12, 15));
    });

    test('startOfWeek respects the first day of the week', () {
      final wed = DateTime(2026, 11, 25, 14);
      expect(startOfWeek(wed, DateTime.monday), DateTime(2026, 11, 23));
      expect(startOfWeek(wed, DateTime.sunday), DateTime(2026, 11, 22));
      expect(startOfWeek(wed, DateTime.saturday), DateTime(2026, 11, 21));
    });

    test('monthGridDays covers whole weeks around the month', () {
      final days = monthGridDays(DateTime(2026, 11, 10), DateTime.monday);
      expect(days.length % 7, 0);
      expect(days.first, DateTime(2026, 10, 26));
      expect(days.last, DateTime(2026, 12, 6));
      expect(days.every((d) => d.hour == 0), isTrue);
      // February 2026 starts on a Sunday: 4 rows Sunday-first, 5 Monday-first.
      expect(monthGridDays(DateTime(2026, 2), DateTime.sunday).length, 28);
      expect(monthGridDays(DateTime(2026, 2), DateTime.monday).length, 35);
    });

    test('all-day dates survive storage encoding unchanged', () {
      final d = DateTime(2026, 3, 29);
      expect(decodeDateTime(encodeDateTime(d, allDay: true), allDay: true), d);
      final t = DateTime(2026, 3, 29, 2, 30);
      expect(decodeDateTime(encodeDateTime(t, allDay: false), allDay: false), t);
    });
  });

  group('time calculations', () {
    test('formatTime honours 12/24-hour setting', () {
      final d = DateTime(2026, 1, 1, 15, 5);
      expect(formatTime(d, true), '15:05');
      expect(formatTime(d, false).replaceAll(' ', ' '), '3:05 PM');
    });

    test('formatReminder describes offsets', () {
      expect(formatReminder(0), 'At time of event');
      expect(formatReminder(5), '5 minutes before');
      expect(formatReminder(60), '1 hour before');
      expect(formatReminder(1440), '1 day before');
      expect(formatReminder(90), '90 minutes before');
      expect(formatReminder(20160), '2 weeks before');
    });

    test('an event ending at midnight does not spill into the next day', () {
      final e = makeEvent(
          start: DateTime(2026, 11, 23, 22), end: DateTime(2026, 11, 24));
      final o = RecurrenceEngine.expand(
              e, DateTime(2026, 11, 23), DateTime(2026, 11, 25))
          .single;
      expect(o.isMultiDay, isFalse);
      expect(o.coversDay(DateTime(2026, 11, 24)), isFalse);
    });

    test('overlapping events are placed side by side', () {
      // (start, end) in minutes.
      final placed = layoutOverlaps<(int, int)>(
        [(540, 600), (570, 630), (600, 660), (720, 780)],
        startMinute: (e) => e.$1,
        endMinute: (e) => e.$2,
      );
      final byStart = {for (final p in placed) p.startMinute: p};
      expect(byStart[540]!.column, 0);
      expect(byStart[570]!.column, 1);
      // 10:00 reuses the first column once 9:00-10:00 has finished.
      expect(byStart[600]!.column, 0);
      expect(byStart[540]!.columns, 2);
      expect(byStart[600]!.columns, 2);
      // The noon event overlaps nothing and gets the full width.
      expect(byStart[720]!.columns, 1);
    });
  });

  group('recurring events', () {
    final nov = DateTime(2026, 11, 1);
    final dec = DateTime(2026, 12, 1);

    test('a single event appears once, only in a range it overlaps', () {
      final e = makeEvent();
      expect(starts(e, nov, dec), [DateTime(2026, 11, 23, 9)]);
      expect(starts(e, dec, DateTime(2027)), isEmpty);
    });

    test('daily', () {
      final e = makeEvent(recurrence: RecurrenceRule.daily);
      final s = starts(e, DateTime(2026, 11, 23), DateTime(2026, 11, 30));
      expect(s.length, 7);
      expect(s.last, DateTime(2026, 11, 29, 9));
    });

    test('weekly keeps the wall-clock time all year (daylight saving)', () {
      final e = makeEvent(
          start: DateTime(2026, 1, 5, 9, 30), recurrence: RecurrenceRule.weekly);
      final s = starts(e, DateTime(2026), DateTime(2027));
      expect(s.length, 52);
      expect(s.every((d) => d.weekday == DateTime.monday), isTrue);
      expect(s.every((d) => d.hour == 9 && d.minute == 30), isTrue);
    });

    test('every two weeks', () {
      final e = makeEvent(recurrence: RecurrenceRule.biweekly);
      expect(starts(e, nov, DateTime(2027)), [
        DateTime(2026, 11, 23, 9),
        DateTime(2026, 12, 7, 9),
        DateTime(2026, 12, 21, 9),
      ]);
    });

    test('custom weekly on several weekdays', () {
      final e = makeEvent(
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
        ),
      );
      expect(starts(e, DateTime(2026, 11, 23), DateTime(2026, 11, 30)), [
        DateTime(2026, 11, 23, 9),
        DateTime(2026, 11, 25, 9),
        DateTime(2026, 11, 27, 9),
      ]);
    });

    test('monthly on the 31st skips shorter months', () {
      final e = makeEvent(
          start: DateTime(2026, 1, 31, 8), recurrence: RecurrenceRule.monthly);
      expect(
        starts(e, DateTime(2026), DateTime(2026, 8)).map((d) => d.month),
        [1, 3, 5, 7],
      );
    });

    test('yearly on 29 February only occurs in leap years', () {
      final e = makeEvent(
        start: DateTime(2024, 2, 29),
        allDay: true,
        recurrence: RecurrenceRule.yearly,
      );
      expect(
        starts(e, DateTime(2024), DateTime(2033)).map((d) => d.year),
        [2024, 2028, 2032],
      );
    });

    test('ends on the until date (inclusive)', () {
      final e = makeEvent(
        recurrence:
            RecurrenceRule.daily.withEnd(until: DateTime(2026, 11, 25)),
      );
      expect(starts(e, nov, dec).length, 3);
    });

    test('ends after a number of occurrences', () {
      final e = makeEvent(recurrence: RecurrenceRule.weekly.withEnd(count: 4));
      final s = starts(e, nov, DateTime(2028));
      expect(s.length, 4);
      expect(s.last, DateTime(2026, 12, 14, 9));
    });

    test('excluded dates are skipped but still count towards the total', () {
      final e = makeEvent(
        recurrence: RecurrenceRule.daily.withEnd(count: 3),
        exDates: [DateTime(2026, 11, 24, 9)],
      );
      expect(starts(e, nov, dec),
          [DateTime(2026, 11, 23, 9), DateTime(2026, 11, 25, 9)]);
    });

    test('far-future ranges give the same result as iterating from the start',
        () {
      final e = makeEvent(
        start: DateTime(2020, 1, 1, 7),
        recurrence: const RecurrenceRule(
            frequency: RecurrenceFrequency.daily, interval: 3),
      );
      final s = starts(e, DateTime(2030, 6, 1), DateTime(2030, 6, 10));
      expect(s, isNotEmpty);
      for (final d in s) {
        expect(daysBetween(DateTime(2020, 1, 1), d) % 3, 0);
      }
      expect(s.length, 3);
    });

    test('multi-day occurrences are found from any day they cover', () {
      final e = makeEvent(
        start: DateTime(2026, 11, 27),
        end: DateTime(2026, 11, 29),
        allDay: true,
        recurrence: RecurrenceRule.weekly,
      );
      final o = RecurrenceEngine.expand(
          e, DateTime(2026, 11, 29), DateTime(2026, 11, 30));
      expect(o.single.start, DateTime(2026, 11, 27));
      expect(o.single.isMultiDay, isTrue);
      expect(o.single.coversDay(DateTime(2026, 11, 28)), isTrue);
      expect(o.single.coversDay(DateTime(2026, 11, 30)), isFalse);
    });

    test('rule round-trips through JSON and describes itself', () {
      final rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        weekdays: const {DateTime.tuesday, DateTime.thursday},
        until: DateTime(2027, 1, 31),
      );
      expect(RecurrenceRule.fromJson(rule.toJson()), rule);
      expect(rule.describe(), 'Every 2 weeks on Tue, Thu, until 2027-01-31');
      expect(rule.toRRule(),
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;UNTIL=20270131T235959');
    });
  });
}
