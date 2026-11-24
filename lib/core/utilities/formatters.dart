import 'package:intl/intl.dart';

import 'date_utils.dart';

String formatTime(DateTime d, bool use24Hour) =>
    (use24Hour ? DateFormat.Hm() : DateFormat.jm()).format(d);

/// "Mon, Nov 23" (adds the year when it is not the current one).
String formatDayShort(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return d.year == n.year
      ? DateFormat('EEE, MMM d').format(d)
      : DateFormat('EEE, MMM d, y').format(d);
}

/// "Monday, November 23, 2026".
String formatDayLong(DateTime d) => DateFormat.yMMMMEEEEd().format(d);

String formatMonthYear(DateTime d) => DateFormat.yMMMM().format(d);

/// "Today", "Tomorrow", "Yesterday" or a short date.
String formatRelativeDay(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return switch (daysBetween(n, d)) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => formatDayShort(d, now: n),
  };
}

/// Time range of an occurrence, e.g. "9:00 AM – 10:30 AM" or
/// "Mon, Nov 23, 9:00 AM – Tue, Nov 24, 11:00 AM".
String formatRange(DateTime start, DateTime end,
    {required bool allDay, required bool use24Hour}) {
  if (allDay) {
    return isSameDay(start, end)
        ? '${formatDayShort(start)} · All day'
        : '${formatDayShort(start)} – ${formatDayShort(end)}';
  }
  final s = formatTime(start, use24Hour);
  final e = formatTime(end, use24Hour);
  if (isSameDay(start, end)) {
    return start == end
        ? '${formatDayShort(start)} · $s'
        : '${formatDayShort(start)} · $s – $e';
  }
  return '${formatDayShort(start)}, $s – ${formatDayShort(end)}, $e';
}

/// Reminder offset label, e.g. "At time of event", "15 minutes before".
String formatReminder(int minutes, {String subject = 'event'}) {
  if (minutes == 0) return 'At time of $subject';
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'} before';
  if (minutes % (60 * 24 * 7) == 0) return unit(minutes ~/ (60 * 24 * 7), 'week');
  if (minutes % (60 * 24) == 0) return unit(minutes ~/ (60 * 24), 'day');
  if (minutes % 60 == 0) return unit(minutes ~/ 60, 'hour');
  return unit(minutes, 'minute');
}

/// Preset reminder choices offered in pickers.
const List<int> reminderPresets = [0, 5, 10, 15, 30, 60, 60 * 24];

const List<String> weekdayLabelsShort = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

const List<String> weekdayLabelsLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
