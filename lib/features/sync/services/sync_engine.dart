import 'dart:convert';

import '../../../data/models/calendar_event.dart';
import '../../../data/repositories/repositories.dart';
import 'google_event_mapper.dart';
import 'remote_calendar_api.dart';

/// What one sync run did.
class SyncResult {
  int pulled = 0;
  int pushed = 0;
  int removedLocally = 0;
  int removedRemotely = 0;

  /// Events whose repeat rule this app cannot show (first date only).
  int unsupportedRepeats = 0;
}

/// Keys used in [SyncStateRepository].
class SyncKeys {
  const SyncKeys._();
  static const account = 'account';
  static const syncToken = 'syncToken';
  static const lastSyncMs = 'lastSyncMs';
  static const defaultReminders = 'defaultReminders';
}

/// Two-way sync between local events and a cloud calendar.
///
/// **Pull**: asks the cloud for everything that changed since the last run
/// (using its sync token) and applies it locally. **Push**: uploads local
/// deletions, then every local event changed since it was last in step.
///
/// Conflicts (an event changed on both sides) are settled by time: the more
/// recent change wins. An event deleted in the cloud is deleted locally.
class SyncEngine {
  SyncEngine({
    required this.events,
    required this.state,
    required this.api,
    required this.timeZone,
    required this.now,
  });

  final EventRepository events;
  final SyncStateRepository state;
  final RemoteCalendarApi api;

  /// The device's IANA time zone name, e.g. "Europe/Paris".
  final String timeZone;
  final DateTime Function() now;

  Future<SyncResult> sync() async {
    final result = SyncResult();
    await _pull(result);
    await _push(result);
    await state.write(
        SyncKeys.lastSyncMs, '${now().millisecondsSinceEpoch}');
    return result;
  }

  // ---- Pull ---------------------------------------------------------------

  Future<void> _pull(SyncResult result) async {
    final saved = await state.readAll();
    var token = saved[SyncKeys.syncToken];
    var defaults = _decodeReminders(saved[SyncKeys.defaultReminders]);

    final items = <Map<String, dynamic>>[];
    String? nextToken;
    for (var attempt = 0;; attempt++) {
      items.clear();
      try {
        String? page;
        do {
          final p = await api.list(syncToken: token, pageToken: page);
          items.addAll(p.items);
          if (p.defaultReminders.isNotEmpty) defaults = p.defaultReminders;
          page = p.nextPageToken;
          nextToken = p.nextSyncToken ?? nextToken;
        } while (page != null);
        break;
      } on SyncTokenExpired {
        // The cloud forgot our place: list everything again. Local links
        // (remote ids) make the full listing merge cleanly.
        if (attempt > 0) rethrow;
        token = null;
      }
    }

    // Events deleted here whose deletion has not been sent yet. The cloud
    // may still report them (as unchanged or as just uploaded); they must
    // not come back to life.
    final deleting = (await state.pendingDeletions()).toSet();

    final local = await events.getAll();
    final byRemote = <String, CalendarEvent>{
      for (final e in local)
        if (e.remoteId != null) e.remoteId!: e,
    };
    final byId = {for (final e in local) e.id: e};

    Future<void> save(CalendarEvent e) async {
      await events.upsert(e);
      byId[e.id] = e;
      if (e.remoteId != null) byRemote[e.remoteId!] = e;
    }

    Future<void> remove(CalendarEvent e) async {
      await events.delete(e.id);
      byId.remove(e.id);
      if (e.remoteId != null) byRemote.remove(e.remoteId);
      result.removedLocally++;
    }

    /// Hides one date of a local series without marking it as changed.
    Future<void> exclude(CalendarEvent master, DateTime date) async {
      final current = byId[master.id] ?? master;
      if (current.exDates.contains(date)) return;
      await save(current.copyWith(exDates: [...current.exDates, date]));
    }

    // Series and single events first, so instances can find their series.
    final masters = items.where((r) => r['recurringEventId'] == null);
    final instances = items.where((r) => r['recurringEventId'] != null);

    for (final r in masters) {
      final id = r['id'] as String?;
      if (id == null || deleting.contains(id)) continue;
      final existing = byRemote[id];

      if (GoogleEventMapper.isCancelled(r)) {
        if (existing != null) await remove(existing);
        continue;
      }
      if (existing != null && existing.remoteEtag == r['etag']) continue;
      if (existing != null && _localWins(existing, r)) continue;

      final mapped = GoogleEventMapper.fromRemote(
        r,
        existing: existing,
        defaultReminders: defaults,
        seriesId: existing?.seriesId,
        originalStart: existing?.originalStart,
        now: now(),
      );
      if (mapped == null) continue;

      // Dates already excluded locally stay excluded. The cloud reports a
      // deleted or modified date of a series once, as a separate item, and
      // does not repeat it in the series' own rule.
      await save(mapped.copyWith(
        exDates: mapped.isRecurring
            ? {...mapped.exDates, ...?existing?.exDates}.toList()
            : const [],
      ));
      result.pulled++;
      if (mapped.remoteRecurrence != null) result.unsupportedRepeats++;
    }

    for (final r in instances) {
      final id = r['id'] as String?;
      if (id == null || deleting.contains(id)) continue;
      final existing = byRemote[id];
      final master = byRemote[r['recurringEventId']];
      final original = GoogleEventMapper.parsePoint(r['originalStartTime'])?.$1;

      if (GoogleEventMapper.isCancelled(r)) {
        // One date of a series was deleted in the cloud.
        if (existing != null) await remove(existing);
        if (master != null && original != null) await exclude(master, original);
        continue;
      }
      if (existing != null && existing.remoteEtag == r['etag']) continue;
      if (existing != null && _localWins(existing, r)) continue;

      final mapped = GoogleEventMapper.fromRemote(
        r,
        existing: existing,
        defaultReminders: defaults,
        seriesId: master?.id,
        originalStart: master == null ? null : original,
        now: now(),
      );
      if (mapped == null) continue;
      await save(mapped);
      if (master != null && original != null) await exclude(master, original);
      result.pulled++;
    }

    if (nextToken != null) await state.write(SyncKeys.syncToken, nextToken);
    await state.write(SyncKeys.defaultReminders, jsonEncode(defaults));
  }

  /// True when the local copy has unsent changes newer than the cloud's.
  bool _localWins(CalendarEvent local, Map<String, dynamic> remote) {
    if (!local.needsSync) return false;
    final updated = GoogleEventMapper.remoteUpdated(remote);
    return updated == null || local.updatedAt.isAfter(updated);
  }

  static List<int> _decodeReminders(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final m in jsonDecode(raw) as List) (m as num).toInt()];
    } catch (_) {
      return const [];
    }
  }

  // ---- Push ---------------------------------------------------------------

  Future<void> _push(SyncResult result) async {
    for (final remoteId in await state.pendingDeletions()) {
      try {
        await api.delete(remoteId);
      } on RemoteNotFound {
        // Already gone: nothing left to do.
      }
      await state.removePendingDeletion(remoteId);
      result.removedRemotely++;
    }

    final all = await events.getAll();
    for (final e in all.where((e) => e.needsSync)) {
      // Dates that the cloud already holds as modified instances of this
      // series must not also be written as excluded dates.
      final instanceDates = e.remoteId == null
          ? const <DateTime>{}
          : {
              for (final c in all)
                if (c.seriesId == e.id &&
                    c.originalStart != null &&
                    (c.remoteId ?? '').startsWith('${e.remoteId}_'))
                  c.originalStart!,
            };
      final body = GoogleEventMapper.toRemote(e,
          timeZone: timeZone, skipExDates: instanceDates);

      Map<String, dynamic> saved;
      if (e.remoteId == null) {
        saved = await api.insert(body);
      } else {
        try {
          saved = await api.patch(e.remoteId!, body);
        } on RemoteNotFound {
          // Deleted in the cloud while it was being edited here: the local
          // edit is newer, so the event is created again.
          saved = await api.insert(body);
        }
      }
      await events.upsert(e.copyWith(
        remoteId: () => saved['id'] as String?,
        remoteEtag: () => saved['etag'] as String?,
        syncedAt: () => e.updatedAt,
      ));
      result.pushed++;
    }
  }
}
