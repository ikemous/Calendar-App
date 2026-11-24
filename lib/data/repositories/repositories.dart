import '../models/app_settings.dart';
import '../models/calendar_event.dart';
import '../models/category.dart';
import '../models/task.dart';

/// Storage contracts. The app only ever talks to these interfaces, so the
/// SQLite implementations can later be wrapped or replaced by a syncing
/// implementation without touching features or UI.

abstract interface class EventRepository {
  Future<List<CalendarEvent>> getAll();
  Future<void> upsert(CalendarEvent event);
  Future<void> upsertAll(Iterable<CalendarEvent> events);
  Future<void> delete(String id);
  Future<void> deleteAll();
}

abstract interface class TaskRepository {
  Future<List<Task>> getAll();
  Future<void> upsert(Task task);
  Future<void> upsertAll(Iterable<Task> tasks);
  Future<void> delete(String id);
  Future<void> deleteAll();
}

abstract interface class CategoryRepository {
  Future<List<Category>> getAll();
  Future<void> upsert(Category category);
  Future<void> upsertAll(Iterable<Category> categories);

  /// Deletes the category and clears it from any events and tasks using it.
  Future<void> delete(String id);
  Future<void> deleteAll();
}

/// Bookkeeping for cloud sync: small key/value state plus the list of
/// events deleted locally that still need deleting in the cloud.
abstract interface class SyncStateRepository {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String? value);
  Future<List<String>> pendingDeletions();
  Future<void> addPendingDeletion(String remoteId);
  Future<void> removePendingDeletion(String remoteId);
  Future<void> clearPendingDeletions();
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
