import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/id.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/recurrence_rule.dart';

/// Converts between this app's events and Google Calendar API event JSON.
///
/// Fields Google has no place for (notes, priority, colour, category) travel
/// in the event's private extended properties, so they survive a round trip
/// and reach the user's other devices.
class GoogleEventMapper {
  const GoogleEventMapper._();

  static const _notesKey = 'calApp.notes';
  static const _priorityKey = 'calApp.priority';
  static const _colorKey = 'calApp.color';
  static const _categoryKey = 'calApp.category';

  /// Google allows at most five reminder overrides, up to four weeks ahead.
  static const int maxReminders = 5;
  static const int maxReminderMinutes = 40320;

  static const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  // ---- Local -> Google ---------------------------------------------------

  /// Request body for creating or patching [e].
  ///
  /// [timeZone] is the device's IANA zone name; Google needs it to expand
  /// recurring events. [skipExDates] are excluded dates that Google already
  /// represents as modified instances and must not be written as EXDATEs.
  static Map<String, dynamic> toRemote(
    CalendarEvent e, {
    required String timeZone,
    Set<DateTime> skipExDates = const {},
  }) {
    Map<String, dynamic> point(DateTime d, {bool endOfAllDay = false}) =>
        e.allDay
            ? {
                // All-day ends are exclusive in Google.
                'date': _isoDate(endOfAllDay ? addDays(d, 1) : d),
                'dateTime': null,
                'timeZone': null,
              }
            : {
                'dateTime': d.toUtc().toIso8601String(),
                'timeZone': timeZone,
                'date': null,
              };

    final rule = e.recurrence;
    final reminders = (e.reminders.toSet().toList()..sort())
        .where((m) => m >= 0 && m <= maxReminderMinutes)
        .take(maxReminders);

    return {
      'summary': e.title,
      'description': e.description,
      'location': e.location,
      'start': point(e.start),
      'end': point(e.end, endOfAllDay: true),
      // An unsupported remote rule is never overwritten.
      if (e.remoteRecurrence == null)
        'recurrence': rule == null
            ? null
            : [
                'RRULE:${_rrule(rule, e)}',
                for (final x in e.exDates)
                  if (!skipExDates.contains(x))
                    e.allDay
                        ? 'EXDATE;VALUE=DATE:${_date(x)}'
                        : 'EXDATE:${_utcStamp(x)}',
              ],
      'reminders': {
        'useDefault': false,
        'overrides': [
          for (final m in reminders) {'method': 'popup', 'minutes': m},
        ],
      },
      'extendedProperties': {
        'private': {
          _notesKey: e.notes,
          _priorityKey: '${e.priority.index}',
          _colorKey: e.colorValue?.toString() ?? '',
          _categoryKey: e.categoryId ?? '',
        },
      },
    };
  }

  static String _rrule(RecurrenceRule r, CalendarEvent e) {
    final until = r.until;
    return [
      'FREQ=${r.frequency.name.toUpperCase()}',
      if (r.interval > 1) 'INTERVAL=${r.interval}',
      if (r.frequency == RecurrenceFrequency.weekly && r.weekdays.isNotEmpty)
        'BYDAY=${(r.weekdays.toList()..sort()).map((d) => _days[d - 1]).join(',')}',
      if (r.frequency == RecurrenceFrequency.monthly &&
          r.weekOrdinal != null &&
          r.weekdays.isNotEmpty)
        'BYDAY=${r.weekOrdinal}${_days[r.weekdays.first - 1]}',
      if (r.count != null) 'COUNT=${r.count}',
      if (until != null)
        e.allDay
            ? 'UNTIL=${_date(until)}'
            : 'UNTIL=${_utcStamp(DateTime(until.year, until.month, until.day, 23, 59, 59))}',
    ].join(';');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Compact `yyyymmdd`, as used inside RRULE and EXDATE lines.
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  static String _utcStamp(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}'
        'T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  // ---- Google -> Local ---------------------------------------------------

  static bool isCancelled(Map<String, dynamic> r) => r['status'] == 'cancelled';

  /// Parses a Google `start`, `end` or `originalStartTime` object. Returns
  /// the local time and whether it is an all-day date.
  static (DateTime, bool)? parsePoint(Object? point) {
    if (point is! Map) return null;
    final date = point['date'];
    if (date is String) {
      final d = DateTime.tryParse(date);
      return d == null ? null : (DateTime(d.year, d.month, d.day), true);
    }
    final dateTime = point['dateTime'];
    if (dateTime is String) {
      final d = DateTime.tryParse(dateTime);
      return d == null ? null : (d.toLocal(), false);
    }
    return null;
  }

  static DateTime? remoteUpdated(Map<String, dynamic> r) {
    final u = r['updated'];
    return u is String ? DateTime.tryParse(u)?.toLocal() : null;
  }

  /// Builds the local event for a Google event. Returns null for items that
  /// cannot be shown (no usable start time).
  ///
  /// [existing] is the local copy, if there is one; its id and local-only
  /// fields are kept. [defaultReminders] are the calendar's defaults, used
  /// when the event says `useDefault`.
  static CalendarEvent? fromRemote(
    Map<String, dynamic> r, {
    CalendarEvent? existing,
    List<int> defaultReminders = const [],
    String? seriesId,
    DateTime? originalStart,
    required DateTime now,
  }) {
    final start = parsePoint(r['start']);
    final end = parsePoint(r['end']);
    if (start == null) return null;
    final allDay = start.$2;
    final s = start.$1;
    var e = end?.$1 ?? s;
    if (allDay) e = addDays(e, -1); // exclusive -> inclusive
    if (e.isBefore(s)) e = s;

    // Repeat rule.
    RecurrenceRule? rule;
    List<String>? unsupported;
    final exDates = <DateTime>[];
    final lines = [for (final l in r['recurrence'] as List? ?? const []) '$l'];
    if (lines.isNotEmpty) {
      final rrules = lines.where((l) => l.startsWith('RRULE')).toList();
      final other = lines.any((l) => l.startsWith('RDATE') || l.startsWith('EXRULE'));
      final parsed = rrules.length == 1 && !other
          ? parseRRule(rrules.single, s)
          : null;
      if (parsed == null) {
        unsupported = lines;
      } else {
        rule = parsed;
        for (final l in lines.where((l) => l.startsWith('EXDATE'))) {
          exDates.addAll(_parseExDates(l, allDay: allDay, time: s));
        }
      }
    }

    // Reminders.
    final reminders = <int>{};
    final rem = r['reminders'];
    if (rem is Map) {
      if (rem['useDefault'] == true) {
        reminders.addAll(defaultReminders);
      } else {
        for (final o in rem['overrides'] as List? ?? const []) {
          final m = (o as Map)['minutes'];
          if (m is num) reminders.add(m.toInt());
        }
      }
    }

    final ext = r['extendedProperties'];
    final private = ext is Map && ext['private'] is Map
        ? (ext['private'] as Map)
        : const {};
    String? prop(String key) {
      final v = private[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final updated = remoteUpdated(r) ?? now;
    final created = r['created'] is String
        ? DateTime.tryParse(r['created'] as String)?.toLocal()
        : null;

    return CalendarEvent(
      id: existing?.id ?? newId(),
      title: (r['summary'] as String?) ?? '',
      description: (r['description'] as String?) ?? '',
      location: (r['location'] as String?) ?? '',
      start: s,
      end: e,
      allDay: allDay,
      notes: private.containsKey(_notesKey)
          ? (private[_notesKey] as String? ?? '')
          : (existing?.notes ?? ''),
      priority: private.containsKey(_priorityKey)
          ? Priority.fromIndex(int.tryParse('${private[_priorityKey]}'))
          : (existing?.priority ?? Priority.none),
      colorValue: private.containsKey(_colorKey)
          ? int.tryParse('${private[_colorKey]}')
          : existing?.colorValue,
      categoryId: private.containsKey(_categoryKey)
          ? prop(_categoryKey)
          : existing?.categoryId,
      reminders: reminders.toList()..sort(),
      recurrence: rule,
      exDates: exDates,
      seriesId: seriesId,
      originalStart: originalStart,
      attachments: existing?.attachments ?? const [],
      remoteId: r['id'] as String?,
      remoteEtag: r['etag'] as String?,
      remoteRecurrence: unsupported,
      // In step with the cloud copy: nothing to upload.
      syncedAt: updated,
      updatedAt: updated,
      createdAt: existing?.createdAt ?? created ?? updated,
    );
  }

  /// Parses an RRULE line into a rule this app can expand, or returns null
  /// if it uses features the app does not support (so the caller can keep
  /// the original instead of showing wrong dates).
  static RecurrenceRule? parseRRule(String line, DateTime start) {
    final value = line.contains(':') ? line.substring(line.indexOf(':') + 1) : line;
    final parts = <String, String>{};
    for (final p in value.split(';')) {
      final i = p.indexOf('=');
      if (i <= 0) continue;
      parts[p.substring(0, i).toUpperCase()] = p.substring(i + 1);
    }

    final frequency = switch (parts['FREQ']) {
      'DAILY' => RecurrenceFrequency.daily,
      'WEEKLY' => RecurrenceFrequency.weekly,
      'MONTHLY' => RecurrenceFrequency.monthly,
      'YEARLY' => RecurrenceFrequency.yearly,
      _ => null,
    };
    if (frequency == null) return null;

    final interval = int.tryParse(parts['INTERVAL'] ?? '1');
    if (interval == null || interval < 1) return null;

    var weekdays = <int>{};
    int? ordinal;
    for (final key in parts.keys) {
      switch (key) {
        case 'FREQ' || 'INTERVAL' || 'COUNT' || 'UNTIL' || 'WKST':
          break;
        case 'BYDAY':
          final days = parts[key]!.split(',');
          if (frequency == RecurrenceFrequency.weekly) {
            for (final d in days) {
              final i = _days.indexOf(d.toUpperCase());
              if (i < 0) return null; // ordinals make no sense weekly
              weekdays.add(i + 1);
            }
          } else if (frequency == RecurrenceFrequency.monthly &&
              days.length == 1) {
            final m = RegExp(r'^(-?\d)([A-Z]{2})$').firstMatch(days.single.toUpperCase());
            final i = m == null ? -1 : _days.indexOf(m.group(2)!);
            final n = m == null ? null : int.tryParse(m.group(1)!);
            if (i < 0 || n == null || !(n == -1 || (n >= 1 && n <= 4))) {
              return null;
            }
            weekdays = {i + 1};
            ordinal = n;
          } else {
            return null;
          }
        case 'BYMONTHDAY':
          // Only "the same day of the month as the start" is supported.
          if (parts[key] != '${start.day}') return null;
        case 'BYMONTH':
          if (frequency != RecurrenceFrequency.yearly ||
              parts[key] != '${start.month}') {
            return null;
          }
        default:
          return null;
      }
    }
    if (frequency == RecurrenceFrequency.weekly &&
        weekdays.length == 1 &&
        weekdays.first == start.weekday) {
      weekdays = {}; // the default: the start's weekday
    }

    final count = parts['COUNT'] == null ? null : int.tryParse(parts['COUNT']!);
    if (parts['COUNT'] != null && (count == null || count < 1)) return null;

    DateTime? until;
    final u = parts['UNTIL'];
    if (u != null) {
      final parsed = _parseStamp(u);
      if (parsed == null) return null;
      until = dateOnly(parsed);
    }

    return RecurrenceRule(
      frequency: frequency,
      interval: interval,
      weekdays: weekdays,
      weekOrdinal: ordinal,
      count: count,
      until: until,
    );
  }

  /// Parses `yyyymmdd`, `yyyymmddThhmmss` (local) or `...Z` (UTC) into local
  /// time.
  static DateTime? _parseStamp(String s) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$')
        .firstMatch(s.trim());
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    if (m.group(4) == null) return DateTime(g(1), g(2), g(3));
    return m.group(7) == 'Z'
        ? DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).toLocal()
        : DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
  }

  static List<DateTime> _parseExDates(String line,
      {required bool allDay, required DateTime time}) {
    final i = line.indexOf(':');
    if (i < 0) return const [];
    return [
      for (final v in line.substring(i + 1).split(','))
        if (_parseStamp(v) case final d?)
          allDay
              ? DateTime(d.year, d.month, d.day)
              // Matched against occurrence starts, which carry the event's
              // clock time.
              : DateTime(d.year, d.month, d.day, d.hour, d.minute),
    ];
  }
}
