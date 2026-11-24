import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import '../models/calendar_event.dart';
import '../models/category.dart';
import '../models/task.dart';
import '../repositories/repositories.dart';

const _replace = ConflictAlgorithm.replace;

class SqliteEventRepository implements EventRepository {
  SqliteEventRepository(this._db);
  final Database _db;

  @override
  Future<List<CalendarEvent>> getAll() async {
    final rows = await _db.query('events', orderBy: 'start_ms');
    return rows.map(CalendarEvent.fromMap).toList();
  }

  @override
  Future<void> upsert(CalendarEvent event) =>
      _db.insert('events', event.toMap(), conflictAlgorithm: _replace);

  @override
  Future<void> upsertAll(Iterable<CalendarEvent> events) async {
    final batch = _db.batch();
    for (final e in events) {
      batch.insert('events', e.toMap(), conflictAlgorithm: _replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> delete(String id) =>
      _db.delete('events', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> deleteAll() => _db.delete('events');
}

class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository(this._db);
  final Database _db;

  @override
  Future<List<Task>> getAll() async {
    final rows = await _db.query('tasks', orderBy: 'created_ms');
    return rows.map(Task.fromMap).toList();
  }

  @override
  Future<void> upsert(Task task) =>
      _db.insert('tasks', task.toMap(), conflictAlgorithm: _replace);

  @override
  Future<void> upsertAll(Iterable<Task> tasks) async {
    final batch = _db.batch();
    for (final t in tasks) {
      batch.insert('tasks', t.toMap(), conflictAlgorithm: _replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> delete(String id) =>
      _db.delete('tasks', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> deleteAll() => _db.delete('tasks');
}

class SqliteCategoryRepository implements CategoryRepository {
  SqliteCategoryRepository(this._db);
  final Database _db;

  @override
  Future<List<Category>> getAll() async {
    final rows = await _db.query('categories', orderBy: 'sort_order, name');
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<void> upsert(Category category) =>
      _db.insert('categories', category.toMap(), conflictAlgorithm: _replace);

  @override
  Future<void> upsertAll(Iterable<Category> categories) async {
    final batch = _db.batch();
    for (final c in categories) {
      batch.insert('categories', c.toMap(), conflictAlgorithm: _replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> delete(String id) => _db.transaction((txn) async {
        await txn.update('events', {'category_id': null},
            where: 'category_id = ?', whereArgs: [id]);
        await txn.update('tasks', {'category_id': null},
            where: 'category_id = ?', whereArgs: [id]);
        await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
      });

  @override
  Future<void> deleteAll() => _db.delete('categories');
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);
  final Database _db;

  @override
  Future<AppSettings> load() async {
    final rows = await _db.query('settings');
    return AppSettings.fromMap({
      for (final r in rows) r['key'] as String: r['value'] as String,
    });
  }

  @override
  Future<void> save(AppSettings settings) async {
    final batch = _db.batch();
    settings.toMap().forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: _replace);
    });
    await batch.commit(noResult: true);
  }
}

class SqliteSyncStateRepository implements SyncStateRepository {
  SqliteSyncStateRepository(this._db);
  final Database _db;

  @override
  Future<Map<String, String>> readAll() async {
    final rows = await _db.query('sync_state');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  @override
  Future<void> write(String key, String? value) => value == null
      ? _db.delete('sync_state', where: 'key = ?', whereArgs: [key])
      : _db.insert('sync_state', {'key': key, 'value': value},
          conflictAlgorithm: _replace);

  @override
  Future<List<String>> pendingDeletions() async {
    final rows = await _db.query('sync_deletions');
    return [for (final r in rows) r['remote_id'] as String];
  }

  @override
  Future<void> addPendingDeletion(String remoteId) => _db.insert(
      'sync_deletions', {'remote_id': remoteId},
      conflictAlgorithm: _replace);

  @override
  Future<void> removePendingDeletion(String remoteId) => _db
      .delete('sync_deletions', where: 'remote_id = ?', whereArgs: [remoteId]);

  @override
  Future<void> clearPendingDeletions() => _db.delete('sync_deletions');
}
