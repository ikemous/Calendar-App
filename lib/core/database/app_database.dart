import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../data/models/category.dart';

/// Opens and migrates the local SQLite database.
///
/// The schema is versioned: bump [schemaVersion] and add a step to
/// [_onUpgrade] for every change so existing installs keep their data when
/// the app is updated.
class AppDatabase {
  static const int schemaVersion = 2;
  static const String fileName = 'calendar.db';

  /// [factory] and [path] exist so tests can run against an in-memory
  /// database; the app uses the platform defaults.
  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        icon TEXT NOT NULL DEFAULT 'label',
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        all_day INTEGER NOT NULL DEFAULT 0,
        category_id TEXT,
        color INTEGER,
        priority INTEGER NOT NULL DEFAULT 0,
        reminders TEXT NOT NULL DEFAULT '[]',
        recurrence TEXT,
        ex_dates TEXT NOT NULL DEFAULT '[]',
        series_id TEXT,
        original_start_ms INTEGER,
        attachments TEXT NOT NULL DEFAULT '[]',
        remote_id TEXT,
        remote_etag TEXT,
        synced_ms INTEGER,
        remote_recurrence TEXT,
        created_ms INTEGER NOT NULL,
        updated_ms INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_events_start ON events(start_ms)');
    batch.execute('CREATE INDEX idx_events_series ON events(series_id)');
    batch.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        due_ms INTEGER,
        has_due_time INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        category_id TEXT,
        completed INTEGER NOT NULL DEFAULT 0,
        completed_ms INTEGER,
        reminder_minutes INTEGER,
        created_ms INTEGER NOT NULL,
        updated_ms INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_events_remote ON events(remote_id)');
    batch.execute('CREATE INDEX idx_tasks_due ON tasks(due_ms)');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    batch.execute(_createSyncState);
    batch.execute(_createSyncDeletions);
    for (final c in Category.defaults) {
      batch.insert('categories', c.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Key/value state of the cloud sync (account, sync token, last run).
  static const _createSyncState = '''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''';

  /// Cloud ids of events deleted locally that still have to be deleted in
  /// the cloud calendar.
  static const _createSyncDeletions = '''
      CREATE TABLE sync_deletions (
        remote_id TEXT PRIMARY KEY
      )''';

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    // Add one `if (from < N)` block per schema version. Never drop user data.
    if (from < 2) {
      // Version 2: links between local events and a synced cloud calendar.
      final batch = db.batch();
      batch.execute('ALTER TABLE events ADD COLUMN remote_id TEXT');
      batch.execute('ALTER TABLE events ADD COLUMN remote_etag TEXT');
      batch.execute('ALTER TABLE events ADD COLUMN synced_ms INTEGER');
      batch.execute('ALTER TABLE events ADD COLUMN remote_recurrence TEXT');
      batch.execute('CREATE INDEX idx_events_remote ON events(remote_id)');
      batch.execute(_createSyncState);
      batch.execute(_createSyncDeletions);
      await batch.commit(noResult: true);
    }
  }
}
