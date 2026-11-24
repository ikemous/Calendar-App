import 'dart:convert';

import '../../core/utilities/date_utils.dart';
import 'recurrence_rule.dart';

enum Priority {
  none('None'),
  low('Low'),
  medium('Medium'),
  high('High');

  const Priority(this.label);
  final String label;

  static Priority fromIndex(int? i) =>
      (i != null && i >= 0 && i < values.length) ? values[i] : none;
}

/// A calendar event. For recurring events this is the series "master"; the
/// individual dates are produced by the recurrence engine.
///
/// All-day events store [start] and [end] as local midnights, with [end]
/// being the last day (inclusive).
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.description = '',
    this.notes = '',
    this.location = '',
    this.categoryId,
    this.colorValue,
    this.priority = Priority.none,
    this.reminders = const [],
    this.recurrence,
    this.exDates = const [],
    this.seriesId,
    this.originalStart,
    this.attachments = const [],
    this.remoteId,
    this.remoteEtag,
    this.syncedAt,
    this.remoteRecurrence,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String description;
  final String notes;
  final String location;
  final String? categoryId;

  /// Optional per-event colour (ARGB). Falls back to the category colour.
  final int? colorValue;
  final Priority priority;

  /// Reminder offsets in minutes before the start (0 = at event time).
  final List<int> reminders;
  final RecurrenceRule? recurrence;

  /// Occurrence starts removed from the series (deleted or detached).
  final List<DateTime> exDates;

  /// Set on an event that was detached from a series by a "this event only"
  /// edit: the id of the series it came from and the occurrence it replaced.
  final String? seriesId;
  final DateTime? originalStart;

  /// File references. Reserved for future attachment support.
  final List<String> attachments;

  /// Id and version tag of this event in the synced cloud calendar, if any.
  final String? remoteId;
  final String? remoteEtag;

  /// Value of [updatedAt] when this event was last in step with the cloud
  /// copy. See [needsSync].
  final DateTime? syncedAt;

  /// The cloud event's repeat rule when it is one this app cannot represent.
  /// Such an event is shown on its first date only, and its rule is left
  /// untouched when changes are uploaded.
  final List<String>? remoteRecurrence;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRecurring => recurrence != null;

  /// True when this event has local changes that have not been uploaded.
  bool get needsSync =>
      remoteId == null || syncedAt == null || updatedAt.isAfter(syncedAt!);

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? description,
    String? notes,
    String? location,
    String? Function()? categoryId,
    int? Function()? colorValue,
    Priority? priority,
    List<int>? reminders,
    RecurrenceRule? Function()? recurrence,
    List<DateTime>? exDates,
    String? Function()? seriesId,
    DateTime? Function()? originalStart,
    List<String>? attachments,
    String? Function()? remoteId,
    String? Function()? remoteEtag,
    DateTime? Function()? syncedAt,
    List<String>? Function()? remoteRecurrence,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        start: start ?? this.start,
        end: end ?? this.end,
        allDay: allDay ?? this.allDay,
        description: description ?? this.description,
        notes: notes ?? this.notes,
        location: location ?? this.location,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        colorValue: colorValue != null ? colorValue() : this.colorValue,
        priority: priority ?? this.priority,
        reminders: reminders ?? this.reminders,
        recurrence: recurrence != null ? recurrence() : this.recurrence,
        exDates: exDates ?? this.exDates,
        seriesId: seriesId != null ? seriesId() : this.seriesId,
        originalStart:
            originalStart != null ? originalStart() : this.originalStart,
        attachments: attachments ?? this.attachments,
        remoteId: remoteId != null ? remoteId() : this.remoteId,
        remoteEtag: remoteEtag != null ? remoteEtag() : this.remoteEtag,
        syncedAt: syncedAt != null ? syncedAt() : this.syncedAt,
        remoteRecurrence: remoteRecurrence != null
            ? remoteRecurrence()
            : this.remoteRecurrence,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Flat map used both for the SQLite row and for JSON backups.
  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'notes': notes,
        'location': location,
        'start_ms': encodeDateTime(start, allDay: allDay),
        'end_ms': encodeDateTime(end, allDay: allDay),
        'all_day': allDay ? 1 : 0,
        'category_id': categoryId,
        'color': colorValue,
        'priority': priority.index,
        'reminders': jsonEncode(reminders),
        'recurrence':
            recurrence == null ? null : jsonEncode(recurrence!.toJson()),
        'ex_dates': jsonEncode(
            [for (final d in exDates) encodeDateTime(d, allDay: allDay)]),
        'series_id': seriesId,
        'original_start_ms': originalStart == null
            ? null
            : encodeDateTime(originalStart!, allDay: allDay),
        'attachments': jsonEncode(attachments),
        'remote_id': remoteId,
        'remote_etag': remoteEtag,
        'synced_ms': syncedAt?.millisecondsSinceEpoch,
        'remote_recurrence':
            remoteRecurrence == null ? null : jsonEncode(remoteRecurrence),
        'created_ms': createdAt.millisecondsSinceEpoch,
        'updated_ms': updatedAt.millisecondsSinceEpoch,
      };

  factory CalendarEvent.fromMap(Map<String, Object?> m) {
    final allDay = (m['all_day'] as num?)?.toInt() == 1;
    List<dynamic> list(String key) {
      final raw = m[key];
      if (raw is String && raw.isNotEmpty) return jsonDecode(raw) as List;
      return const [];
    }

    final rec = m['recurrence'];
    final orig = m['original_start_ms'] as num?;
    final synced = m['synced_ms'] as num?;
    final remoteRule = m['remote_recurrence'];
    return CalendarEvent(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      notes: (m['notes'] as String?) ?? '',
      location: (m['location'] as String?) ?? '',
      start: decodeDateTime((m['start_ms'] as num).toInt(), allDay: allDay),
      end: decodeDateTime((m['end_ms'] as num).toInt(), allDay: allDay),
      allDay: allDay,
      categoryId: m['category_id'] as String?,
      colorValue: (m['color'] as num?)?.toInt(),
      priority: Priority.fromIndex((m['priority'] as num?)?.toInt()),
      reminders: [for (final r in list('reminders')) (r as num).toInt()],
      recurrence: rec is String && rec.isNotEmpty
          ? RecurrenceRule.fromJson(jsonDecode(rec) as Map<String, dynamic>)
          : null,
      exDates: [
        for (final d in list('ex_dates'))
          decodeDateTime((d as num).toInt(), allDay: allDay),
      ],
      seriesId: m['series_id'] as String?,
      originalStart:
          orig == null ? null : decodeDateTime(orig.toInt(), allDay: allDay),
      attachments: [for (final a in list('attachments')) a as String],
      remoteId: m['remote_id'] as String?,
      remoteEtag: m['remote_etag'] as String?,
      syncedAt: synced == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(synced.toInt()),
      remoteRecurrence: remoteRule is String && remoteRule.isNotEmpty
          ? [for (final r in jsonDecode(remoteRule) as List) r as String]
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (m['created_ms'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['updated_ms'] as num?)?.toInt() ?? 0),
    );
  }
}

/// One concrete date of an event (the only one, for non-recurring events).
class EventOccurrence {
  const EventOccurrence({
    required this.event,
    required this.start,
    required this.end,
  });

  final CalendarEvent event;
  final DateTime start;
  final DateTime end;

  bool get allDay => event.allDay;

  /// First calendar day this occurrence covers.
  DateTime get firstDay => dateOnly(start);

  /// Last calendar day this occurrence covers. A timed event ending exactly
  /// at midnight does not spill into the following day.
  DateTime get lastDay {
    if (allDay) return dateOnly(end);
    final endsAtMidnight = end.hour == 0 && end.minute == 0 && end.isAfter(start);
    return endsAtMidnight ? addDays(dateOnly(end), -1) : dateOnly(end);
  }

  bool get isMultiDay => !isSameDay(firstDay, lastDay);

  bool coversDay(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(firstDay) && !d.isAfter(lastDay);
  }
}
