import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../data/repositories/repositories.dart';
import 'calendar_auth.dart';
import 'remote_calendar_api.dart';

/// One of the phone's calendars that events can be added to.
class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.name,
    required this.account,
    this.accountType = '',
    this.color,
    this.primary = false,
  });

  final String id;
  final String name;

  /// The account the calendar belongs to, e.g. a Gmail address.
  final String account;
  final String accountType;
  final int? color;
  final bool primary;

  /// Android keeps these in step with Google Calendar by itself.
  bool get isGoogle => accountType == 'com.google';

  /// Shown as the connected "account".
  String get label =>
      account.isEmpty || account == name ? name : '$name · $account';
}

/// Raw access to the phone's calendar storage. Rows are plain maps with the
/// calendar provider's own columns; see [DeviceCalendarApi] for their
/// meaning.
abstract interface class DeviceCalendarPlatform {
  Future<bool> hasPermission();

  /// Shows the system permission prompt if needed.
  Future<bool> requestPermission();
  Future<List<DeviceCalendarInfo>> calendars();
  Future<List<Map<String, dynamic>>> events(String calendarId);
  Future<Map<String, dynamic>?> event(int id);
  Future<int> insert(String calendarId, Map<String, dynamic> values);

  /// Returns false if the event no longer exists.
  Future<bool> update(int id, Map<String, dynamic> values);
  Future<void> delete(int id);
}

/// [DeviceCalendarPlatform] for Android (`DeviceCalendar.kt`).
class AndroidDeviceCalendarPlatform implements DeviceCalendarPlatform {
  const AndroidDeviceCalendarPlatform();

  static const _channel = MethodChannel('calendar_app/device_calendar');

  static Map<String, dynamic> _map(Object? o) =>
      Map<String, dynamic>.from(o as Map);

  @override
  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<List<DeviceCalendarInfo>> calendars() async => [
        for (final c in await _channel.invokeListMethod<Object?>('calendars') ??
            const [])
          DeviceCalendarInfo(
            id: _map(c)['id'] as String,
            name: _map(c)['name'] as String? ?? '',
            account: _map(c)['account'] as String? ?? '',
            accountType: _map(c)['accountType'] as String? ?? '',
            color: _map(c)['color'] as int?,
            primary: _map(c)['primary'] == true,
          ),
      ];

  @override
  Future<List<Map<String, dynamic>>> events(String calendarId) async => [
        for (final e in await _channel.invokeListMethod<Object?>(
                'events', {'calendarId': calendarId}) ??
            const [])
          _map(e),
      ];

  @override
  Future<Map<String, dynamic>?> event(int id) async {
    final row = await _channel.invokeMethod<Object?>('event', {'id': id});
    return row == null ? null : _map(row);
  }

  @override
  Future<int> insert(String calendarId, Map<String, dynamic> values) async =>
      (await _channel.invokeMethod<int>(
          'insert', {'calendarId': calendarId, 'values': values}))!;

  @override
  Future<bool> update(int id, Map<String, dynamic> values) async =>
      await _channel
          .invokeMethod<bool>('update', {'id': id, 'values': values}) ??
      false;

  @override
  Future<void> delete(int id) =>
      _channel.invokeMethod<void>('delete', {'id': id});
}

/// "Signing in" to a phone calendar: calendar permission plus the user's
/// choice of calendar. No Google sign-in or client ids are involved.
class DeviceCalendarAuth implements CalendarAuth {
  DeviceCalendarAuth(this.platform, this.state);

  final DeviceCalendarPlatform platform;
  final SyncStateRepository state;

  static const calendarIdKey = 'deviceCalendarId';

  DeviceCalendarInfo? _chosen;

  @override
  bool get isConfigured => true;

  /// Asks for calendar access and lists the calendars to choose from.
  /// Returns null if access was refused.
  Future<List<DeviceCalendarInfo>?> loadCalendars() async {
    if (!await platform.requestPermission()) return null;
    return platform.calendars();
  }

  /// The calendar the next [signIn] connects to.
  void choose(DeviceCalendarInfo calendar) => _chosen = calendar;

  @override
  Future<String?> signIn() async {
    final calendar = _chosen;
    if (calendar == null) return null;
    await state.write(calendarIdKey, calendar.id);
    return calendar.label;
  }

  /// The chosen calendar's id stands in for an access token.
  @override
  Future<String?> accessToken() async {
    if (!await platform.hasPermission()) return null;
    return (await state.readAll())[calendarIdKey];
  }

  @override
  Future<void> signOut() async {
    _chosen = null;
    await state.write(calendarIdKey, null);
  }
}

/// Presents one phone calendar through the interface the sync engine uses
/// for Google, so the same engine, conflict rules and tests apply.
///
/// Rows are translated to and from Google's event shape. The phone's
/// calendar has no change feed for ordinary apps, so changes are detected
/// by fingerprint: the "sync token" is the list of event ids and their
/// fingerprints as of the previous listing.
class DeviceCalendarApi implements RemoteCalendarApi {
  DeviceCalendarApi(this.platform, this.calendarId);

  final DeviceCalendarPlatform platform;
  final String calendarId;

  // ---- Listing ------------------------------------------------------------

  @override
  Future<RemotePage> list({String? syncToken, String? pageToken}) async {
    Map<String, dynamic>? previous;
    if (syncToken != null) {
      try {
        previous = jsonDecode(syncToken) as Map<String, dynamic>;
      } catch (_) {
        throw const SyncTokenExpired();
      }
    }

    final current = <String, String>{};
    final items = <Map<String, dynamic>>[];
    for (final row in await platform.events(calendarId)) {
      final item = toItem(row);
      if (item == null) continue;
      final id = item['id'] as String;
      current[id] = item['etag'] as String;
      if (previous == null || previous[id] != item['etag']) items.add(item);
    }
    // Anything listed last time and missing now was deleted on the phone.
    for (final id in previous?.keys ?? const <String>[]) {
      if (current.containsKey(id)) continue;
      final master = _masterOf(id);
      items.add({
        'id': id,
        'status': 'cancelled',
        'recurringEventId': ?master,
      });
    }
    return RemotePage(items: items, nextSyncToken: jsonEncode(current));
  }

  // ---- Writing ------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> body) async {
    final id = await platform.insert(calendarId, toValues(body));
    return _saved(id);
  }

  @override
  Future<Map<String, dynamic>> patch(String id, Map<String, dynamic> body) async {
    final row = _rowId(id);
    if (row == null || !await platform.update(row, toValues(body))) {
      throw const RemoteNotFound();
    }
    return _saved(row);
  }

  @override
  Future<void> delete(String id) async {
    final row = _rowId(id);
    if (row != null) await platform.delete(row);
  }

  Future<Map<String, dynamic>> _saved(int id) async {
    final row = await platform.event(id);
    final item = row == null ? null : toItem(row);
    if (item == null) throw const RemoteNotFound();
    return item;
  }

  // ---- Ids ----------------------------------------------------------------

  // A changed single date of a series is its own row on the phone. Its id is
  // written "<series>_x<row>", so it can be recognised as belonging to the
  // series, as Google's instance ids are.
  static String _itemId(Map<String, dynamic> row) {
    final original = row['originalId'];
    return original == null ? '${row['id']}' : '${original}_x${row['id']}';
  }

  static String? _masterOf(String id) {
    final i = id.indexOf('_x');
    return i < 0 ? null : id.substring(0, i);
  }

  static int? _rowId(String id) {
    final i = id.indexOf('_x');
    return int.tryParse(i < 0 ? id : id.substring(i + 2));
  }

  // ---- Phone row -> Google-shaped item -----------------------------------

  /// Converts a calendar row. Returns null for rows without a start time.
  static Map<String, dynamic>? toItem(Map<String, dynamic> row) {
    final startMs = (row['dtstart'] as num?)?.toInt();
    if (startMs == null) return null;
    final allDay = row['allDay'] == true;
    final endMs = (row['dtend'] as num?)?.toInt() ??
        startMs + _durationMs(row['duration'] as String?, allDay: allDay);

    Map<String, dynamic> point(int ms) {
      final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      // All-day events are stored as midnight UTC of their date.
      return allDay
          ? {'date': _isoDate(utc)}
          : {'dateTime': utc.toIso8601String()};
    }

    final rrule = (row['rrule'] as String?)?.trim();
    final exdate = _exDateValues(row['exdate'] as String?, allDay: allDay);
    final original = row['originalId'];
    final originalMs = (row['originalInstanceTime'] as num?)?.toInt();
    final reminders = [
      for (final m in row['reminders'] as List? ?? const []) (m as num).toInt(),
    ]..sort();

    final item = <String, dynamic>{
      'id': _itemId(row),
      'status': row['cancelled'] == true ? 'cancelled' : 'confirmed',
      'summary': row['title'] as String? ?? '',
      'description': row['description'] as String? ?? '',
      'location': row['location'] as String? ?? '',
      'start': point(startMs),
      'end': point(endMs),
      if (rrule != null && rrule.isNotEmpty)
        'recurrence': [
          'RRULE:$rrule',
          if (exdate.isNotEmpty)
            allDay
                ? 'EXDATE;VALUE=DATE:${exdate.join(',')}'
                : 'EXDATE:${exdate.join(',')}',
        ],
      'reminders': {
        'useDefault': false,
        'overrides': [
          for (final m in reminders) {'method': 'popup', 'minutes': m},
        ],
      },
      if (original != null) 'recurringEventId': '$original',
      if (original != null && originalMs != null)
        'originalStartTime': point(originalMs),
    };
    // The fingerprint: any change to what sync cares about changes it.
    item['etag'] = _fingerprint(jsonEncode(item));
    return item;
  }

  /// Length of an RFC 2445 duration such as `P3600S`, `PT1H30M` or `P1D`.
  static int _durationMs(String? duration, {required bool allDay}) {
    final fallback = allDay ? Duration.millisecondsPerDay : 0;
    if (duration == null) return fallback;
    final m = RegExp(
            r'^P(?:(\d+)W)?(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$')
        .firstMatch(duration.trim().toUpperCase());
    if (m == null) return fallback;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return Duration(
      days: g(1) * 7 + g(2),
      hours: g(3),
      minutes: g(4),
      seconds: g(5),
    ).inMilliseconds;
  }

  /// The stamps of an EXDATE column, which may be prefixed with a time zone
  /// (`Europe/Paris;20260101T100000`). All-day stamps are cut to the date.
  static List<String> _exDateValues(String? exdate, {required bool allDay}) {
    if (exdate == null || exdate.trim().isEmpty) return const [];
    final values = exdate.substring(exdate.lastIndexOf(';') + 1);
    return [
      for (final v in values.split(','))
        if (v.trim().length >= 8)
          allDay ? v.trim().substring(0, 8) : v.trim(),
    ];
  }

  // ---- Google-shaped body -> phone row values ----------------------------

  /// Column values for creating or updating an event from the body the
  /// sync engine would send to Google.
  static Map<String, dynamic> toValues(Map<String, dynamic> body) {
    final start = body['start'] as Map;
    final end = body['end'] as Map;
    final allDay = start['date'] != null;

    int ms(Map point) {
      if (allDay) {
        final d = DateTime.parse(point['date'] as String);
        return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
      }
      return DateTime.parse(point['dateTime'] as String)
          .millisecondsSinceEpoch;
    }

    final values = <String, dynamic>{
      'title': body['summary'] ?? '',
      'description': body['description'] ?? '',
      'location': body['location'] ?? '',
      'reminders': [
        for (final o in (body['reminders'] as Map?)?['overrides'] as List? ??
            const [])
          ((o as Map)['minutes'] as num).toInt(),
      ],
    };
    // No 'recurrence' key at all means the event repeats in a way the app
    // cannot represent: its timing is left exactly as it is on the phone.
    if (!body.containsKey('recurrence')) {
      return values..['keepTiming'] = true;
    }

    final startMs = ms(start);
    final endMs = ms(end);
    final lines = [for (final l in body['recurrence'] as List? ?? const []) '$l'];
    String? after(String prefix) {
      for (final l in lines) {
        if (l.startsWith(prefix)) return l.substring(l.indexOf(':') + 1);
      }
      return null;
    }

    final rrule = after('RRULE');
    final exdates = [
      for (final l in lines)
        if (l.startsWith('EXDATE'))
          for (final v in l.substring(l.indexOf(':') + 1).split(','))
            // All-day dates are stored at midnight UTC, like the event.
            allDay && v.length == 8 ? '${v}T000000Z' : v,
    ];
    final length = Duration(milliseconds: endMs - startMs);
    return values
      ..addAll({
        'dtstart': startMs,
        'allDay': allDay,
        'timezone': allDay ? 'UTC' : (start['timeZone'] ?? 'UTC'),
        // Android wants an end for single events and a duration for
        // repeating ones, never both.
        'dtend': rrule == null ? endMs : null,
        'duration': rrule == null
            ? null
            : allDay
                ? 'P${length.inDays}D'
                : 'P${length.inSeconds}S',
        'rrule': rrule,
        'exdate': rrule == null || exdates.isEmpty ? null : exdates.join(','),
      });
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// FNV-1a, stable across app restarts (unlike [String.hashCode]).
  static String _fingerprint(String text) {
    var a = 0x811c9dc5;
    var b = 0x01000193;
    for (final unit in text.codeUnits) {
      a = ((a ^ unit) * 0x01000193) & 0xFFFFFFFF;
      b = ((b * 31) + unit) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16)}${b.toRadixString(16)}${text.length}';
  }
}
