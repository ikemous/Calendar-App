import 'package:calendar_app/data/repositories/repositories.dart';
import 'package:calendar_app/features/sync/services/calendar_auth.dart';
import 'package:calendar_app/features/sync/services/remote_calendar_api.dart';

import 'helpers.dart';

class MemorySyncStateRepository implements SyncStateRepository {
  MemorySyncStateRepository([Map<String, String> initial = const {}])
      : values = {...initial};
  final Map<String, String> values;
  final Set<String> deletions = {};

  @override
  Future<Map<String, String>> readAll() async => {...values};
  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
  @override
  Future<List<String>> pendingDeletions() async => deletions.toList();
  @override
  Future<void> addPendingDeletion(String remoteId) async =>
      deletions.add(remoteId);
  @override
  Future<void> removePendingDeletion(String remoteId) async =>
      deletions.remove(remoteId);
  @override
  Future<void> clearPendingDeletions() async => deletions.clear();
}

class FakeCalendarAuth implements CalendarAuth {
  FakeCalendarAuth({this.email = 'me@example.com'});

  /// Account returned by [signIn]; null simulates the user cancelling.
  String? email;
  String? token = 'token';
  bool configured = true;
  int signOuts = 0;

  @override
  bool get isConfigured => configured;
  @override
  Future<String?> signIn() async => email;
  @override
  Future<String?> accessToken() async => token;
  @override
  Future<void> signOut() async => signOuts++;
}

/// An in-memory stand-in for the Google Calendar events API. It mimics the
/// behaviours sync depends on: ids and etags, patch semantics, cancelled
/// tombstones, incremental listing with sync tokens, paging and token expiry.
class FakeGoogleCalendar implements RemoteCalendarApi {
  FakeGoogleCalendar({this.pageSize = 250});

  final int pageSize;
  final Map<String, Map<String, dynamic>> items = {};

  /// Ids in the order they changed; a sync token is a position in this log.
  final List<String> _log = [];
  int _counter = 0;
  DateTime clock = testNow;
  List<int> defaultReminders = [30];

  /// When true, the next incremental listing reports an expired token.
  bool expireTokens = false;
  bool offline = false;
  int inserts = 0;
  int patches = 0;
  int deletes = 0;

  Iterable<Map<String, dynamic>> get live =>
      items.values.where((i) => i['status'] != 'cancelled');

  Map<String, dynamic> bySummary(String summary) =>
      live.firstWhere((i) => i['summary'] == summary);

  void _touch(Map<String, dynamic> item) {
    _counter++;
    item['etag'] = '"etag$_counter"';
    item['updated'] = clock.toUtc().toIso8601String();
    _log.add(item['id'] as String);
  }

  static Map<String, dynamic> _clean(Map<String, dynamic> body) => {
        for (final e in body.entries)
          if (e.value != null)
            e.key: e.value is Map
                ? _clean(Map<String, dynamic>.from(e.value as Map))
                : e.value,
      };

  // ---- Changes made "in Google" (by another device or the web) ------------

  Map<String, dynamic> remoteAdd(Map<String, dynamic> body, {String? id}) {
    final item = {
      ..._clean(body),
      'id': id ?? 'g${++_counter}',
      'status': 'confirmed',
    };
    items[item['id'] as String] = item;
    _touch(item);
    return item;
  }

  void remoteEdit(String id, Map<String, dynamic> changes) {
    final item = items[id]!..addAll(changes);
    _touch(item);
  }

  void remoteDelete(String id) {
    final item = items[id]!;
    item['status'] = 'cancelled';
    _touch(item);
  }

  // ---- RemoteCalendarApi ---------------------------------------------------

  @override
  Future<RemotePage> list({String? syncToken, String? pageToken}) async {
    if (offline) throw Exception('offline');
    List<Map<String, dynamic>> all;
    if (syncToken == null) {
      all = live.toList();
    } else {
      if (expireTokens) {
        expireTokens = false;
        throw const SyncTokenExpired();
      }
      final from = int.parse(syncToken.substring(4));
      final changed = <String>{..._log.skip(from)};
      all = [for (final id in changed) items[id]!];
    }
    final offset = pageToken == null ? 0 : int.parse(pageToken);
    final end = (offset + pageSize).clamp(0, all.length);
    final last = end >= all.length;
    return RemotePage(
      items: [for (final i in all.sublist(offset, end)) {...i}],
      nextPageToken: last ? null : '$end',
      nextSyncToken: last ? 'tok-${_log.length}' : null,
      defaultReminders: defaultReminders,
    );
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> body) async {
    if (offline) throw Exception('offline');
    inserts++;
    return {...remoteAdd(body)};
  }

  @override
  Future<Map<String, dynamic>> patch(String id, Map<String, dynamic> body) async {
    if (offline) throw Exception('offline');
    final item = items[id];
    if (item == null || item['status'] == 'cancelled') {
      throw const RemoteNotFound();
    }
    patches++;
    body.forEach((key, value) {
      if (value == null) {
        item.remove(key);
      } else if (value is Map) {
        item[key] = _clean(Map<String, dynamic>.from(value));
      } else {
        item[key] = value;
      }
    });
    _touch(item);
    return {...item};
  }

  @override
  Future<void> delete(String id) async {
    if (offline) throw Exception('offline');
    final item = items[id];
    if (item == null || item['status'] == 'cancelled') {
      throw const RemoteNotFound();
    }
    deletes++;
    remoteDelete(id);
  }
}
