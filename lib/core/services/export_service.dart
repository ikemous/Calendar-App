import 'dart:convert';

import '../../data/models/app_settings.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../utilities/date_utils.dart';

/// A complete snapshot of the user's data.
class BackupData {
  const BackupData({
    required this.events,
    required this.tasks,
    required this.categories,
    this.settings,
  });

  final List<CalendarEvent> events;
  final List<Task> tasks;
  final List<Category> categories;
  final AppSettings? settings;
}

/// Thrown when a file is not a readable backup.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Serialises calendar data to JSON (lossless backup), CSV and iCalendar.
/// Pure functions: no file or database access.
class ExportService {
  const ExportService._();

  static const String backupFormat = 'calendar_app_backup';
  static const int backupVersion = 1;

  // ---- JSON ---------------------------------------------------------------

  static String toJson(BackupData data, {DateTime? exportedAt}) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': backupFormat,
        'version': backupVersion,
        'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'categories': [for (final c in data.categories) c.toMap()],
        'events': [for (final e in data.events) e.toMap()],
        'tasks': [for (final t in data.tasks) t.toMap()],
        if (data.settings != null) 'settings': data.settings!.toMap(),
      });

  /// Parses and fully validates a backup. Throws [BackupFormatException]
  /// without side effects if anything is wrong, so callers can safely parse
  /// first and only then modify stored data.
  static BackupData fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const BackupFormatException('This file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != backupFormat) {
      throw const BackupFormatException(
          'This file is not a Calendar backup.');
    }
    final version = decoded['version'];
    if (version is! int || version > backupVersion) {
      throw const BackupFormatException(
          'This backup was made by a newer version of the app.');
    }
    List<Map<String, Object?>> rows(String key) => [
          for (final r in (decoded as Map)[key] as List? ?? const [])
            Map<String, Object?>.from(r as Map),
        ];
    try {
      final settings = decoded['settings'];
      return BackupData(
        categories: rows('categories').map(Category.fromMap).toList(),
        events: rows('events').map(CalendarEvent.fromMap).toList(),
        tasks: rows('tasks').map(Task.fromMap).toList(),
        settings: settings is Map
            ? AppSettings.fromMap(
                settings.map((k, v) => MapEntry('$k', '$v')))
            : null,
      );
    } catch (_) {
      throw const BackupFormatException(
          'This backup is damaged and cannot be read.');
    }
  }

  // ---- CSV ----------------------------------------------------------------

  static String eventsToCsv(
      Iterable<CalendarEvent> events, Map<String, Category> categories) {
    final b = StringBuffer()
      ..writeln(_csvRow([
        'Title', 'Start', 'End', 'All day', 'Location', 'Category',
        'Priority', 'Repeats', 'Description', 'Notes',
      ]));
    final sorted = events.toList()..sort((a, b) => a.start.compareTo(b.start));
    for (final e in sorted) {
      b.writeln(_csvRow([
        e.title,
        _csvDate(e.start, e.allDay),
        _csvDate(e.end, e.allDay),
        e.allDay ? 'Yes' : 'No',
        e.location,
        categories[e.categoryId]?.name ?? '',
        e.priority == Priority.none ? '' : e.priority.label,
        e.recurrence?.describe() ?? '',
        e.description,
        e.notes,
      ]));
    }
    return b.toString();
  }

  static String _csvDate(DateTime d, bool allDay) {
    final date = '${d.year}-${_two(d.month)}-${_two(d.day)}';
    return allDay ? date : '$date ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _csvRow(List<String> cells) => cells.map(_csvCell).join(',');

  static String _csvCell(String v) {
    // Prefix cells a spreadsheet would run as a formula.
    final safe = v.startsWith(RegExp(r'[=+\-@\t\r]')) ? "'$v" : v;
    return safe.contains(RegExp(r'[",\n\r]'))
        ? '"${safe.replaceAll('"', '""')}"'
        : safe;
  }

  // ---- iCalendar ----------------------------------------------------------

  static String toIcs(
    Iterable<CalendarEvent> events,
    Map<String, Category> categories, {
    Iterable<Task> tasks = const [],
    DateTime? now,
  }) {
    final stamp = _icsUtc(now ?? DateTime.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Calendar App//EN',
      'CALSCALE:GREGORIAN',
    ];
    for (final e in events) {
      // Recurring events use floating local time so every occurrence keeps
      // its wall-clock time across daylight-saving changes.
      String stampOf(DateTime d) =>
          e.isRecurring ? _icsLocal(d) : _icsUtc(d);
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${e.id}@calendar-app')
        ..add('DTSTAMP:$stamp');
      if (e.allDay) {
        lines
          ..add('DTSTART;VALUE=DATE:${_icsDate(e.start)}')
          ..add('DTEND;VALUE=DATE:${_icsDate(addDays(e.end, 1))}');
      } else {
        lines
          ..add('DTSTART:${stampOf(e.start)}')
          ..add('DTEND:${stampOf(e.end)}');
      }
      lines.add('SUMMARY:${_icsText(e.title)}');
      final description = [e.description, e.notes]
          .where((s) => s.trim().isNotEmpty)
          .join('\n\n');
      if (description.isNotEmpty) {
        lines.add('DESCRIPTION:${_icsText(description)}');
      }
      if (e.location.isNotEmpty) lines.add('LOCATION:${_icsText(e.location)}');
      final category = categories[e.categoryId];
      if (category != null) lines.add('CATEGORIES:${_icsText(category.name)}');
      if (e.priority != Priority.none) {
        lines.add('PRIORITY:${_icsPriority(e.priority)}');
      }
      if (e.recurrence != null) {
        lines.add('RRULE:${e.recurrence!.toRRule()}');
        for (final x in e.exDates) {
          lines.add(e.allDay
              ? 'EXDATE;VALUE=DATE:${_icsDate(x)}'
              : 'EXDATE:${_icsLocal(x)}');
        }
      }
      for (final minutes in e.reminders) {
        lines
          ..add('BEGIN:VALARM')
          ..add('ACTION:DISPLAY')
          ..add('DESCRIPTION:${_icsText(e.title)}')
          ..add('TRIGGER:-PT${minutes}M')
          ..add('END:VALARM');
      }
      lines.add('END:VEVENT');
    }
    for (final t in tasks) {
      lines
        ..add('BEGIN:VTODO')
        ..add('UID:${t.id}@calendar-app')
        ..add('DTSTAMP:$stamp')
        ..add('SUMMARY:${_icsText(t.title)}');
      if (t.description.isNotEmpty) {
        lines.add('DESCRIPTION:${_icsText(t.description)}');
      }
      final due = t.dueDate;
      if (due != null) {
        lines.add(t.hasDueTime
            ? 'DUE:${_icsUtc(due)}'
            : 'DUE;VALUE=DATE:${_icsDate(due)}');
      }
      if (t.priority != Priority.none) {
        lines.add('PRIORITY:${_icsPriority(t.priority)}');
      }
      lines
        ..add('STATUS:${t.completed ? 'COMPLETED' : 'NEEDS-ACTION'}')
        ..add('END:VTODO');
    }
    lines.add('END:VCALENDAR');
    return '${lines.map(_fold).join('\r\n')}\r\n';
  }

  static int _icsPriority(Priority p) => switch (p) {
        Priority.high => 1,
        Priority.medium => 5,
        Priority.low => 9,
        Priority.none => 0,
      };

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _icsDate(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';

  static String _icsLocal(DateTime d) =>
      '${_icsDate(d)}T${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

  static String _icsUtc(DateTime d) => '${_icsLocal(d.toUtc())}Z';

  static String _icsText(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  /// RFC 5545 line folding: lines longer than 75 octets continue on the
  /// next line after a single space.
  static String _fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = StringBuffer();
    var width = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (width + size > 75) {
        out.write('\r\n ');
        width = 1;
      }
      out.write(ch);
      width += size;
    }
    return out.toString();
  }
}
