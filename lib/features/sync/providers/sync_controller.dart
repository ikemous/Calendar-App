import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/services/app_services.dart';
import '../../../data/datasources/sync_service.dart';
import '../../events/providers/events_provider.dart';
import '../services/calendar_auth.dart';
import '../services/device_calendar.dart';
import '../services/remote_calendar_api.dart';
import '../services/sync_engine.dart';

/// Access to the phone's own calendars. Overridden in tests.
final deviceCalendarPlatformProvider = Provider<DeviceCalendarPlatform>(
    (ref) => const AndroidDeviceCalendarPlatform());

/// How the app reaches the calendar it syncs with. Overridden in tests.
///
/// With Google client ids in `GoogleConfig`, the app signs in to Google and
/// talks to Google Calendar directly. Without them, on Android, it syncs
/// with a calendar already on the phone instead, which needs no setup:
/// Android keeps a Google account's calendars in step with Google itself.
final calendarAuthProvider = Provider<CalendarAuth>((ref) {
  final google = GoogleCalendarAuth();
  if (!google.isConfigured &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android) {
    return DeviceCalendarAuth(
      ref.watch(deviceCalendarPlatformProvider),
      ref.watch(syncStateRepositoryProvider),
    );
  }
  return google;
});

/// Builds the API client for an access token. Overridden in tests.
final remoteCalendarApiFactoryProvider =
    Provider<RemoteCalendarApi Function(String accessToken)>((ref) {
  final auth = ref.watch(calendarAuthProvider);
  // For a phone calendar, the "token" is the chosen calendar's id.
  if (auth is DeviceCalendarAuth) {
    return (calendarId) => DeviceCalendarApi(auth.platform, calendarId);
  }
  return (token) => GoogleCalendarApi(accessToken: token);
});

/// The device's IANA time zone name. Overridden in tests.
final timeZoneNameProvider = Provider<Future<String> Function()>(
  (ref) => () async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  },
);

class SyncStatus {
  const SyncStatus({
    this.account,
    this.lastSync,
    this.syncing = false,
    this.error,
    this.lastResult,
  });

  /// Email of the connected Google account; null when not connected.
  final String? account;
  final DateTime? lastSync;
  final bool syncing;

  /// Why the last sync failed, in words fit for the user.
  final String? error;
  final SyncResult? lastResult;

  bool get connected => account != null;
}

/// Connects a Google account and runs two-way sync.
class SyncController extends Notifier<SyncStatus> {
  static const Duration _debounce = Duration(seconds: 4);
  Timer? _timer;
  bool _again = false;

  @override
  SyncStatus build() {
    ref.onDispose(() => _timer?.cancel());
    final saved = ref.watch(bootstrapProvider).syncState;
    final last = int.tryParse(saved[SyncKeys.lastSyncMs] ?? '');
    return SyncStatus(
      account: saved[SyncKeys.account],
      lastSync:
          last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  bool get isConfigured => ref.read(calendarAuthProvider).isConfigured;

  /// Whether sync goes through a calendar on the phone rather than a direct
  /// Google sign-in.
  bool get usesDeviceCalendar =>
      ref.read(calendarAuthProvider) is DeviceCalendarAuth;

  /// Signs in and runs the first sync. Returns false if the user cancelled.
  /// Throws [CalendarAuthException] if sign-in fails.
  Future<bool> connect() async {
    final email = await ref.read(calendarAuthProvider).signIn();
    if (email == null) return false;
    final store = ref.read(syncStateRepositoryProvider);
    final saved = await store.readAll();
    final previous = saved[SyncKeys.account] ?? saved[_lastAccountKey];
    if (previous != null && previous != email) {
      // A different account: forget links to the previous one's events so
      // they are not confused with events in this calendar.
      await _unlinkAll();
    }
    await store.write(SyncKeys.account, email);
    state = SyncStatus(account: email);
    await syncNow();
    return true;
  }

  /// Stops syncing. Events stay on the device and in Google Calendar.
  Future<void> disconnect() async {
    _timer?.cancel();
    await ref.read(calendarAuthProvider).signOut();
    final store = ref.read(syncStateRepositoryProvider);
    final previous = state.account;
    await store.write(SyncKeys.account, null);
    await store.write(SyncKeys.syncToken, null);
    // Remembered, so reconnecting the same account merges instead of
    // duplicating; see connect().
    if (previous != null) await store.write(_lastAccountKey, previous);
    state = const SyncStatus();
  }

  static const _lastAccountKey = 'lastAccount';

  Future<void> _unlinkAll() async {
    final repo = ref.read(eventRepositoryProvider);
    final store = ref.read(syncStateRepositoryProvider);
    final all = await repo.getAll();
    await repo.upsertAll([
      for (final e in all)
        if (e.remoteId != null)
          e.copyWith(
            remoteId: () => null,
            remoteEtag: () => null,
            syncedAt: () => null,
            remoteRecurrence: () => null,
          ),
    ]);
    await store.write(SyncKeys.syncToken, null);
    await store.clearPendingDeletions();
    await ref.read(eventsProvider.notifier).reload();
  }

  /// Called after local data was wiped or replaced wholesale. Nothing is
  /// deleted from the cloud; the next sync lists everything again.
  Future<void> resetAfterDataReset() async {
    final store = ref.read(syncStateRepositoryProvider);
    await store.write(SyncKeys.syncToken, null);
    await store.clearPendingDeletions();
  }

  /// Schedules a sync shortly after a local change, if connected.
  void requestSync() {
    if (!state.connected) return;
    _timer?.cancel();
    _timer = Timer(_debounce, syncNow);
  }

  /// Runs a sync now. Safe to call at any time: if one is already running,
  /// another is queued to follow it.
  Future<void> syncNow() async {
    if (!state.connected) return;
    if (state.syncing) {
      _again = true;
      return;
    }
    _timer?.cancel();
    state = SyncStatus(
        account: state.account, lastSync: state.lastSync, syncing: true);
    SyncResult? result;
    String? error;
    try {
      result = await _run();
    } on RemoteUnauthorized {
      error = usesDeviceCalendar
          ? 'Calendar access was removed. Disconnect and connect again.'
          : 'Google needs you to sign in again.';
    } on RemoteApiException catch (e) {
      error = e.statusCode == 403
          ? 'Google Calendar refused the request. Check that calendar '
              'access was granted.'
          : 'Google Calendar could not be reached (error ${e.statusCode}).';
    } catch (e) {
      // Usually no connection. Only the error type is logged: event data
      // is private.
      debugPrint('Sync failed: ${e.runtimeType}');
      error = usesDeviceCalendar
          ? 'Could not sync with the phone calendar.'
          : 'Could not sync. Check your internet connection.';
    }
    if (!ref.mounted) return;
    state = SyncStatus(
      account: state.account,
      lastSync: error == null ? ref.read(clockProvider)() : state.lastSync,
      error: error,
      lastResult: result ?? state.lastResult,
    );
    if (_again) {
      _again = false;
      unawaited(syncNow());
    }
  }

  Future<SyncResult> _run() async {
    final token = await ref.read(calendarAuthProvider).accessToken();
    if (token == null) throw const RemoteUnauthorized();
    final engine = SyncEngine(
      events: ref.read(eventRepositoryProvider),
      state: ref.read(syncStateRepositoryProvider),
      api: ref.read(remoteCalendarApiFactoryProvider)(token),
      timeZone: await ref.read(timeZoneNameProvider)(),
      now: ref.read(clockProvider),
    );
    try {
      return await engine.sync();
    } finally {
      // Show whatever was applied, even if the run stopped part-way.
      if (ref.mounted) {
        await ref.read(eventsProvider.notifier).reload();
        await ref.read(reminderSchedulerProvider).sync();
      }
    }
  }
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Bridges the app's generic "something changed" hook to Google sync.
class _GoogleSyncService implements SyncService {
  _GoogleSyncService(this._ref);
  final Ref _ref;

  @override
  bool get isEnabled => _ref.read(syncControllerProvider).connected;

  @override
  Future<void> recordChanged(String collection, String id) async {
    if (collection == 'events') {
      _ref.read(syncControllerProvider.notifier).requestSync();
    }
  }

  @override
  Future<void> recordDeleted(String collection, String id) =>
      recordChanged(collection, id);

  @override
  Future<void> syncNow() =>
      _ref.read(syncControllerProvider.notifier).syncNow();
}

/// The sync hook the data notifiers report changes to.
final syncServiceProvider =
    Provider<SyncService>((ref) => _GoogleSyncService(ref));
