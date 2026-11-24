import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/calendar/services/recurrence_engine.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/events/services/series_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2027, 1, 1);

  List<DateTime> allStarts(Iterable events) => RecurrenceEngine.occurrencesInRange(
          events.cast(), from, to)
      .map((o) => o.start)
      .toList();

  group('event creation, editing and deletion', () {
    test('a created event is stored and kept in state', () async {
      final bootstrap = memoryBootstrap();
      final c = makeContainer(bootstrap: bootstrap);
      await c.read(eventsProvider.notifier).save(makeEvent(title: 'Dentist'));

      expect(c.read(eventsProvider).single.title, 'Dentist');
      expect((await bootstrap.eventRepository.getAll()).single.title, 'Dentist');
    });

    test('editing replaces the stored event', () async {
      final original = makeEvent();
      final bootstrap = memoryBootstrap(events: [original]);
      final c = makeContainer(bootstrap: bootstrap);
      await c.read(eventsProvider.notifier).editOccurrence(
            master: original,
            occurrenceStart: original.start,
            edited: original.copyWith(title: 'Renamed', location: 'Room 2'),
            scope: RecurrenceScope.all,
          );

      final stored = (await bootstrap.eventRepository.getAll()).single;
      expect(stored.id, original.id);
      expect(stored.title, 'Renamed');
      expect(stored.location, 'Room 2');
      expect(c.read(eventsProvider).single.title, 'Renamed');
    });

    test('deleting removes the event from state and storage', () async {
      final e = makeEvent();
      final bootstrap = memoryBootstrap(events: [e]);
      final c = makeContainer(bootstrap: bootstrap);
      await c.read(eventsProvider.notifier).deleteOccurrence(
            master: e,
            occurrenceStart: e.start,
            scope: RecurrenceScope.all,
          );

      expect(c.read(eventsProvider), isEmpty);
      expect(await bootstrap.eventRepository.getAll(), isEmpty);
    });
  });

  group('recurring series: delete', () {
    final series = makeEvent(recurrence: RecurrenceRule.weekly);
    final second = DateTime(2026, 11, 30, 9);

    test('this event only removes one date', () {
      final change = SeriesEditor.delete(
        master: series,
        occurrenceStart: second,
        scope: RecurrenceScope.thisOnly,
        allEvents: [series],
      );
      expect(change.deletes, isEmpty);
      final s = allStarts(change.upserts);
      expect(s, isNot(contains(second)));
      expect(s, contains(DateTime(2026, 11, 23, 9)));
      expect(s, contains(DateTime(2026, 12, 7, 9)));
    });

    test('this and future ends the series before that date', () {
      final change = SeriesEditor.delete(
        master: series,
        occurrenceStart: second,
        scope: RecurrenceScope.thisAndFuture,
        allEvents: [series],
      );
      expect(allStarts(change.upserts), [DateTime(2026, 11, 23, 9)]);
    });

    test('this and future on the first date deletes the whole series', () {
      final change = SeriesEditor.delete(
        master: series,
        occurrenceStart: series.start,
        scope: RecurrenceScope.thisAndFuture,
        allEvents: [series],
      );
      expect(change.deletes, [series.id]);
    });

    test('entire series deletes the series and its detached events', () {
      final detached = makeEvent(id: 'child')
          .copyWith(seriesId: () => series.id, originalStart: () => second);
      final change = SeriesEditor.delete(
        master: series,
        occurrenceStart: second,
        scope: RecurrenceScope.all,
        allEvents: [series, detached],
      );
      expect(change.deletes, unorderedEquals([series.id, 'child']));
    });
  });

  group('recurring series: edit', () {
    final series = makeEvent(recurrence: RecurrenceRule.weekly);
    final second = DateTime(2026, 11, 30, 9);

    // The form result when the 30 Nov occurrence is moved to 2 pm.
    final moved = series.copyWith(
      title: 'Moved',
      start: DateTime(2026, 11, 30, 14),
      end: DateTime(2026, 11, 30, 15),
    );

    test('this event only detaches a single changed event', () {
      final change = SeriesEditor.edit(
        master: series,
        occurrenceStart: second,
        edited: moved,
        scope: RecurrenceScope.thisOnly,
        allEvents: [series],
      );
      expect(change.upserts.length, 2);
      final master = change.upserts.firstWhere((e) => e.id == series.id);
      final single = change.upserts.firstWhere((e) => e.id != series.id);
      expect(master.title, 'Meeting');
      expect(master.exDates, [second]);
      expect(single.isRecurring, isFalse);
      expect(single.seriesId, series.id);
      expect(single.originalStart, second);
      expect(single.start, DateTime(2026, 11, 30, 14));
      // The calendar shows the moved event instead of the original date.
      final s = allStarts(change.upserts);
      expect(s, contains(DateTime(2026, 11, 30, 14)));
      expect(s, isNot(contains(second)));
    });

    test('this and future splits the series in two', () {
      final change = SeriesEditor.edit(
        master: series,
        occurrenceStart: second,
        edited: moved,
        scope: RecurrenceScope.thisAndFuture,
        allEvents: [series],
      );
      final head = change.upserts.firstWhere((e) => e.id == series.id);
      final tail = change.upserts.firstWhere((e) => e.id != series.id);
      expect(allStarts([head]), [DateTime(2026, 11, 23, 9)]);
      expect(tail.title, 'Moved');
      expect(tail.isRecurring, isTrue);
      expect(allStarts([tail]).first, DateTime(2026, 11, 30, 14));
      expect(allStarts([tail]).every((d) => d.hour == 14), isTrue);
    });

    test('a "repeat N times" series keeps its total when split', () {
      final counted =
          makeEvent(recurrence: RecurrenceRule.weekly.withEnd(count: 5));
      final change = SeriesEditor.edit(
        master: counted,
        occurrenceStart: second,
        edited: counted.copyWith(
            title: 'Later', start: second, end: second.add(const Duration(hours: 1))),
        scope: RecurrenceScope.thisAndFuture,
        allEvents: [counted],
      );
      expect(allStarts(change.upserts).length, 5);
    });

    test('entire series shifts every occurrence, keeping the first date', () {
      final change = SeriesEditor.edit(
        master: series,
        occurrenceStart: second,
        edited: moved,
        scope: RecurrenceScope.all,
        allEvents: [series],
      );
      final updated = change.upserts.single;
      expect(updated.id, series.id);
      expect(updated.title, 'Moved');
      expect(updated.start, DateTime(2026, 11, 23, 14));
      expect(updated.end, DateTime(2026, 11, 23, 15));
    });

    test('turning repeat off for the series leaves one event', () {
      final change = SeriesEditor.edit(
        master: series,
        occurrenceStart: second,
        edited: moved.copyWith(recurrence: () => null),
        scope: RecurrenceScope.all,
        allEvents: [series],
      );
      expect(allStarts(change.upserts), [DateTime(2026, 11, 30, 14)]);
    });
  });
}
