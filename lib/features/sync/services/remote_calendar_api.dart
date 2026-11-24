import 'dart:convert';

import 'package:http/http.dart' as http;

/// One page of an events listing.
class RemotePage {
  const RemotePage({
    required this.items,
    this.nextPageToken,
    this.nextSyncToken,
    this.defaultReminders = const [],
  });

  final List<Map<String, dynamic>> items;
  final String? nextPageToken;

  /// Present on the last page: pass it to the next listing to receive only
  /// what changed since.
  final String? nextSyncToken;

  /// The calendar's default reminder offsets, in minutes.
  final List<int> defaultReminders;
}

/// The saved sync token is no longer valid; start again with a full listing.
class SyncTokenExpired implements Exception {
  const SyncTokenExpired();
}

/// The event does not exist (any more) in the cloud calendar.
class RemoteNotFound implements Exception {
  const RemoteNotFound();
}

/// The access token was rejected.
class RemoteUnauthorized implements Exception {
  const RemoteUnauthorized();
}

class RemoteApiException implements Exception {
  const RemoteApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'Google Calendar error $statusCode: $message';
}

/// The handful of cloud-calendar operations sync needs. The engine only
/// knows this interface, so it can be tested against an in-memory fake and
/// another provider could be added later.
abstract interface class RemoteCalendarApi {
  Future<RemotePage> list({String? syncToken, String? pageToken});
  Future<Map<String, dynamic>> insert(Map<String, dynamic> body);
  Future<Map<String, dynamic>> patch(String id, Map<String, dynamic> body);
  Future<void> delete(String id);
}

/// Google Calendar API v3 over HTTPS, for the user's primary calendar.
class GoogleCalendarApi implements RemoteCalendarApi {
  GoogleCalendarApi({required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;

  static const _host = 'www.googleapis.com';
  static const _base = '/calendar/v3/calendars/primary/events';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Never _fail(http.Response r) {
    if (r.statusCode == 401) throw const RemoteUnauthorized();
    if (r.statusCode == 404 || r.statusCode == 410) throw const RemoteNotFound();
    var message = r.reasonPhrase ?? 'Request failed';
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final m = (body as Map)['error']?['message'];
      if (m is String) message = m;
    } catch (_) {
      // Keep the reason phrase.
    }
    throw RemoteApiException(r.statusCode, message);
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  @override
  Future<RemotePage> list({String? syncToken, String? pageToken}) async {
    final r = await _client.get(
      Uri.https(_host, _base, {
        'maxResults': '250',
        'syncToken': ?syncToken,
        'pageToken': ?pageToken,
      }),
      headers: _headers,
    );
    if (r.statusCode == 410) throw const SyncTokenExpired();
    if (r.statusCode != 200) _fail(r);
    final body = _json(r);
    return RemotePage(
      items: [
        for (final i in body['items'] as List? ?? const [])
          Map<String, dynamic>.from(i as Map),
      ],
      nextPageToken: body['nextPageToken'] as String?,
      nextSyncToken: body['nextSyncToken'] as String?,
      defaultReminders: [
        for (final d in body['defaultReminders'] as List? ?? const [])
          if ((d as Map)['minutes'] is num) (d['minutes'] as num).toInt(),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> body) async {
    final r = await _client.post(Uri.https(_host, _base),
        headers: _headers, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) _fail(r);
    return _json(r);
  }

  @override
  Future<Map<String, dynamic>> patch(String id, Map<String, dynamic> body) async {
    final r = await _client.patch(Uri.https(_host, '$_base/$id'),
        headers: _headers, body: jsonEncode(body));
    if (r.statusCode != 200) _fail(r);
    return _json(r);
  }

  @override
  Future<void> delete(String id) async {
    final r = await _client.delete(Uri.https(_host, '$_base/$id'),
        headers: _headers);
    if (r.statusCode != 204 && r.statusCode != 200) _fail(r);
  }
}
