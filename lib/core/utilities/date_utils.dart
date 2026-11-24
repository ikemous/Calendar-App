/// Calendar date helpers. Everything here works on local wall-clock time and
/// uses calendar arithmetic (not fixed 24h durations) so results stay correct
/// across daylight-saving transitions.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [a] to [b] (negative when [b] is earlier).
int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

/// Adds months, clamping the day to the last day of the target month.
DateTime addMonths(DateTime d, int months) {
  final first = DateTime(d.year, d.month + months, 1);
  final day = d.day.clamp(1, daysInMonth(first.year, first.month));
  return DateTime(first.year, first.month, day, d.hour, d.minute);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// First day of the week containing [d]. [firstDayOfWeek] uses
/// [DateTime.monday]..[DateTime.sunday].
DateTime startOfWeek(DateTime d, int firstDayOfWeek) {
  final diff = (d.weekday - firstDayOfWeek + 7) % 7;
  return addDays(dateOnly(d), -diff);
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

/// The dates shown in a month grid: whole weeks covering the month.
List<DateTime> monthGridDays(DateTime month, int firstDayOfWeek) {
  final first = startOfWeek(startOfMonth(month), firstDayOfWeek);
  final last = DateTime(month.year, month.month + 1, 0);
  final weeks = (daysBetween(first, last) ~/ 7) + 1;
  return [for (var i = 0; i < weeks * 7; i++) addDays(first, i)];
}

/// Weekday numbers in display order, starting at [firstDayOfWeek].
List<int> orderedWeekdays(int firstDayOfWeek) =>
    [for (var i = 0; i < 7; i++) (firstDayOfWeek - 1 + i) % 7 + 1];

/// Combines the calendar date of [date] with the clock time of [time].
DateTime combine(DateTime date, DateTime time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// Storage encoding. Timed values are stored as UTC epoch milliseconds.
/// All-day values are stored as the UTC midnight of their calendar date so
/// that they never shift to another day when the device time zone changes.
int encodeDateTime(DateTime d, {required bool allDay}) => allDay
    ? DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch
    : d.millisecondsSinceEpoch;

DateTime decodeDateTime(int ms, {required bool allDay}) {
  if (!allDay) return DateTime.fromMillisecondsSinceEpoch(ms);
  final u = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return DateTime(u.year, u.month, u.day);
}
