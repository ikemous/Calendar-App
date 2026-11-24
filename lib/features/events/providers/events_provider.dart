import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/services/app_services.dart';
import '../../../data/models/calendar_event.dart';
import '../../sync/providers/sync_controller.dart';
import '../services/series_editor.dart';

/// All stored events (series masters and single events), kept in memory and
/// written through to the repository.
class EventsNotifier extends Notifier<List<CalendarEvent>> {
  @override
  List<CalendarEvent> build() => ref.watch(bootstrapProvider).events;

  CalendarEvent? byId(String id) {
    for (final e in state) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> _apply(SeriesChange change) async {
    final repo = ref.read(eventRepositoryProvider);
    final syncState = ref.read(syncStateRepositoryProvider);
    for (final id in change.deletes) {
      // An event that exists in the cloud calendar must be deleted there
      // too on the next sync.
      final remoteId = byId(id)?.remoteId;
      if (remoteId != null) await syncState.addPendingDeletion(remoteId);
      await repo.delete(id);
    }
    // Keep the link to the cloud copy when an event is saved from a form
    // that was opened before a sync attached it.
    final upserts = [
      for (final e in change.upserts)
        if (e.remoteId == null && byId(e.id)?.remoteId != null)
          e.copyWith(
            remoteId: () => byId(e.id)!.remoteId,
            remoteEtag: () => byId(e.id)!.remoteEtag,
            syncedAt: () => byId(e.id)!.syncedAt,
            remoteRecurrence: () => byId(e.id)!.remoteRecurrence,
          )
        else
          e,
    ];
    if (upserts.isNotEmpty) await repo.upsertAll(upserts);

    final sync = ref.read(syncServiceProvider);
    for (final id in change.deletes) {
      await sync.recordDeleted('events', id);
    }
    for (final e in upserts) {
      await sync.recordChanged('events', e.id);
    }

    final upserted = {for (final e in upserts) e.id: e};
    state = [
      for (final e in state)
        if (!change.deletes.contains(e.id) && !upserted.containsKey(e.id)) e,
      ...upserts,
    ];
    await ref.read(reminderSchedulerProvider).sync();
  }

  /// Creates a new event or replaces a non-recurring one.
  Future<void> save(CalendarEvent event) =>
      _apply(SeriesChange(upserts: [event]));

  /// Applies an edit made to one occurrence of [master].
  Future<void> editOccurrence({
    required CalendarEvent master,
    required DateTime occurrenceStart,
    required CalendarEvent edited,
    required RecurrenceScope scope,
  }) =>
      _apply(SeriesEditor.edit(
        master: master,
        occurrenceStart: occurrenceStart,
        edited: edited,
        scope: scope,
        allEvents: state,
        now: ref.read(clockProvider)(),
      ));

  Future<void> deleteOccurrence({
    required CalendarEvent master,
    required DateTime occurrenceStart,
    required RecurrenceScope scope,
  }) =>
      _apply(SeriesEditor.delete(
        master: master,
        occurrenceStart: occurrenceStart,
        scope: scope,
        allEvents: state,
        now: ref.read(clockProvider)(),
      ));

  /// Re-reads everything from storage (after an import or a wipe).
  Future<void> reload() async {
    state = await ref.read(eventRepositoryProvider).getAll();
  }
}

final eventsProvider =
    NotifierProvider<EventsNotifier, List<CalendarEvent>>(EventsNotifier.new);
