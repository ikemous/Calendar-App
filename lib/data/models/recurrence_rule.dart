import '../../core/utilities/date_utils.dart';

enum RecurrenceFrequency { daily, weekly, monthly, yearly }

/// How an event repeats. A rule ends on [until] (inclusive date), after
/// [count] occurrences, or never when both are null.
class RecurrenceRule {
  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const {},
    this.weekOrdinal,
    this.until,
    this.count,
  }) : assert(interval >= 1);

  final RecurrenceFrequency frequency;
  final int interval;

  /// Weekly rules only: [DateTime.monday]..[DateTime.sunday]. Empty means
  /// "the weekday of the event's start".
  final Set<int> weekdays;

  /// Monthly rules only: repeat on the nth weekday of the month (1-4, or -1
  /// for the last), e.g. "the second Tuesday". The weekday is the single
  /// entry in [weekdays]. Null means "the same day of the month".
  final int? weekOrdinal;
  final DateTime? until;
  final int? count;

  static const daily = RecurrenceRule(frequency: RecurrenceFrequency.daily);
  static const weekly = RecurrenceRule(frequency: RecurrenceFrequency.weekly);
  static const biweekly =
      RecurrenceRule(frequency: RecurrenceFrequency.weekly, interval: 2);
  static const monthly = RecurrenceRule(frequency: RecurrenceFrequency.monthly);
  static const yearly = RecurrenceRule(frequency: RecurrenceFrequency.yearly);

  /// True when this rule is one of the simple presets (no end, no weekdays).
  bool get isPreset =>
      until == null && count == null && weekdays.isEmpty && weekOrdinal == null;

  RecurrenceRule withEnd({DateTime? until, int? count}) => RecurrenceRule(
        frequency: frequency,
        interval: interval,
        weekdays: weekdays,
        weekOrdinal: weekOrdinal,
        until: until,
        count: count,
      );

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'interval': interval,
        if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
        if (weekOrdinal != null) 'weekOrdinal': weekOrdinal,
        if (until != null)
          'until': encodeDateTime(until!, allDay: true),
        if (count != null) 'count': count,
      };

  factory RecurrenceRule.fromJson(Map<String, dynamic> j) => RecurrenceRule(
        frequency: RecurrenceFrequency.values.firstWhere(
          (f) => f.name == j['frequency'],
          orElse: () => RecurrenceFrequency.daily,
        ),
        interval: ((j['interval'] as num?)?.toInt() ?? 1).clamp(1, 999),
        weekdays: {
          for (final w in (j['weekdays'] as List? ?? const []))
            (w as num).toInt(),
        },
        weekOrdinal: (j['weekOrdinal'] as num?)?.toInt(),
        until: j['until'] == null
            ? null
            : decodeDateTime((j['until'] as num).toInt(), allDay: true),
        count: (j['count'] as num?)?.toInt(),
      );

  static const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _icsDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// Human readable summary, e.g. "Every 2 weeks on Mon, Wed".
  String describe() {
    final unit = switch (frequency) {
      RecurrenceFrequency.daily => 'day',
      RecurrenceFrequency.weekly => 'week',
      RecurrenceFrequency.monthly => 'month',
      RecurrenceFrequency.yearly => 'year',
    };
    final b = StringBuffer(
      interval == 1
          ? switch (frequency) {
              RecurrenceFrequency.daily => 'Daily',
              RecurrenceFrequency.weekly => 'Weekly',
              RecurrenceFrequency.monthly => 'Monthly',
              RecurrenceFrequency.yearly => 'Yearly',
            }
          : 'Every $interval ${unit}s',
    );
    if (frequency == RecurrenceFrequency.weekly && weekdays.isNotEmpty) {
      final days = weekdays.toList()..sort();
      b.write(' on ${days.map((d) => _weekdayNames[d - 1]).join(', ')}');
    }
    if (frequency == RecurrenceFrequency.monthly &&
        weekOrdinal != null &&
        weekdays.isNotEmpty) {
      const names = {1: 'first', 2: 'second', 3: 'third', 4: 'fourth', -1: 'last'};
      b.write(' on the ${names[weekOrdinal] ?? '${weekOrdinal}th'} '
          '${_weekdayNames[weekdays.first - 1]}');
    }
    if (until != null) {
      b.write(', until ${until!.year}-${_two(until!.month)}-${_two(until!.day)}');
    } else if (count != null) {
      b.write(', $count times');
    }
    return b.toString();
  }

  /// RFC 5545 RRULE value (without the `RRULE:` prefix).
  String toRRule() {
    final parts = <String>[
      'FREQ=${frequency.name.toUpperCase()}',
      if (interval > 1) 'INTERVAL=$interval',
      if (frequency == RecurrenceFrequency.weekly && weekdays.isNotEmpty)
        'BYDAY=${(weekdays.toList()..sort()).map((d) => _icsDays[d - 1]).join(',')}',
      if (frequency == RecurrenceFrequency.monthly &&
          weekOrdinal != null &&
          weekdays.isNotEmpty)
        'BYDAY=$weekOrdinal${_icsDays[weekdays.first - 1]}',
      if (count != null) 'COUNT=$count',
      if (until != null)
        'UNTIL=${until!.year}${_two(until!.month)}${_two(until!.day)}T235959',
    ];
    return parts.join(';');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule &&
      other.frequency == frequency &&
      other.interval == interval &&
      other.count == count &&
      other.until == until &&
      other.weekOrdinal == weekOrdinal &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(
      frequency, interval, count, until, weekOrdinal,
      Object.hashAllUnordered(weekdays));
}
