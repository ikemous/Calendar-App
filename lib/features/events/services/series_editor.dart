import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/id.dart';
import '../../../data/models/calendar_event.dart';
import '../../calendar/services/recurrence_engine.dart';

/// Which part of a recurring series an edit or delete applies to.
enum RecurrenceScope {
  thisOnly('This event only'),
  thisAndFuture('This and future events'),
  all('Entire series');

  const RecurrenceScope(this.label);
  final String label;
}

/// The storage writes needed to apply a series operation.
class SeriesChange {
  const SeriesChange({this.upserts = const [], this.deletes = const []});
  final List<CalendarEvent> upserts;
  final List<String> deletes;
}

/// Pure functions that work out how editing or deleting one occurrence of a
/// recurring event changes the stored events. Nothing here touches storage.
class SeriesEditor {
  const SeriesEditor._();

  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  static bool _isFirst(CalendarEvent master, DateTime occStart) =>
      RecurrenceEngine.countBefore(master, occStart) == 0;

  static Iterable<CalendarEvent> _children(
          CalendarEvent master, Iterable<CalendarEvent> all) =>
      all.where((e) => e.seriesId == master.id);

  static SeriesChange delete({
    required CalendarEvent master,
    required DateTime occurrenceStart,
    required RecurrenceScope scope,
    required Iterable<CalendarEvent> allEvents,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    if (!master.isRecurring ||
        scope == RecurrenceScope.all ||
        (scope == RecurrenceScope.thisAndFuture &&
            _isFirst(master, occurrenceStart))) {
      return SeriesChange(deletes: [
        master.id,
        for (final c in _children(master, allEvents)) c.id,
      ]);
    }
    if (scope == RecurrenceScope.thisOnly) {
      return SeriesChange(upserts: [
        master.copyWith(
          exDates: [...master.exDates, occurrenceStart],
          updatedAt: stamp,
        ),
      ]);
    }
    // This and future: end the series the day before this occurrence.
    return SeriesChange(
      upserts: [
        master.copyWith(
          recurrence: () => master.recurrence!
              .withEnd(until: addDays(dateOnly(occurrenceStart), -1)),
          updatedAt: stamp,
        ),
      ],
      deletes: [
        for (final c in _children(master, allEvents))
          if (c.originalStart != null &&
              !c.originalStart!.isBefore(occurrenceStart))
            c.id,
      ],
    );
  }

  /// [edited] is the form result: it carries the dates of the occurrence
  /// being edited (not of the series start) plus the new field values.
  static SeriesChange edit({
    required CalendarEvent master,
    required DateTime occurrenceStart,
    required CalendarEvent edited,
    required RecurrenceScope scope,
    required Iterable<CalendarEvent> allEvents,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    if (!master.isRecurring) {
      return SeriesChange(
          upserts: [edited.copyWith(id: master.id, updatedAt: stamp)]);
    }

    final dayShift = daysBetween(occurrenceStart, edited.start);
    final spanDays = daysBetween(edited.start, edited.end);
    DateTime shiftStart(DateTime d) => DateTime(d.year, d.month,
        d.day + dayShift, edited.start.hour, edited.start.minute);
    DateTime endOf(DateTime start) => DateTime(start.year, start.month,
        start.day + spanDays, edited.end.hour, edited.end.minute);

    switch (scope) {
      case RecurrenceScope.thisOnly:
        return SeriesChange(upserts: [
          master.copyWith(
            exDates: [...master.exDates, occurrenceStart],
            updatedAt: stamp,
          ),
          edited.copyWith(
            id: newId(),
            recurrence: () => null,
            exDates: const [],
            seriesId: () => master.id,
            originalStart: () => occurrenceStart,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        ]);

      case RecurrenceScope.all:
        if (edited.recurrence == null) {
          // Repeat was turned off: the series collapses into a single event
          // on the date being edited.
          return SeriesChange(upserts: [
            edited.copyWith(
              id: master.id,
              exDates: const [],
              createdAt: master.createdAt,
              updatedAt: stamp,
            ),
          ]);
        }
        final newStart = shiftStart(master.start);
        return SeriesChange(upserts: [
          edited.copyWith(
            id: master.id,
            start: newStart,
            end: endOf(newStart),
            exDates: [for (final d in master.exDates) shiftStart(d)],
            seriesId: () => master.seriesId,
            originalStart: () => master.originalStart,
            createdAt: master.createdAt,
            updatedAt: stamp,
          ),
        ]);

      case RecurrenceScope.thisAndFuture:
        if (_isFirst(master, occurrenceStart)) {
          return edit(
            master: master,
            occurrenceStart: occurrenceStart,
            edited: edited,
            scope: RecurrenceScope.all,
            allEvents: allEvents,
            now: stamp,
          );
        }
        final oldRule = master.recurrence!;
        var newRule = edited.recurrence;
        // A "repeat N times" rule carried over unchanged continues counting
        // from where the original series left off.
        if (newRule != null &&
            oldRule.count != null &&
            newRule.count == oldRule.count) {
          final remaining = oldRule.count! -
              RecurrenceEngine.countBefore(master, occurrenceStart);
          newRule = newRule.withEnd(count: remaining < 1 ? 1 : remaining);
        }
        final sameTime = _same(occurrenceStart, edited.start);
        final tailId = newId();
        return SeriesChange(upserts: [
          master.copyWith(
            recurrence: () =>
                oldRule.withEnd(until: addDays(dateOnly(occurrenceStart), -1)),
            exDates: [
              for (final d in master.exDates)
                if (d.isBefore(occurrenceStart)) d,
            ],
            updatedAt: stamp,
          ),
          edited.copyWith(
            id: tailId,
            recurrence: () => newRule,
            exDates: [
              if (sameTime)
                for (final d in master.exDates)
                  if (!d.isBefore(occurrenceStart)) d,
            ],
            seriesId: () => null,
            originalStart: () => null,
            createdAt: stamp,
            updatedAt: stamp,
          ),
          for (final c in _children(master, allEvents))
            if (c.originalStart != null &&
                !c.originalStart!.isBefore(occurrenceStart))
              c.copyWith(seriesId: () => tailId, updatedAt: stamp),
        ]);
    }
  }
}
