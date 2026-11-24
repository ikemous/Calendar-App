import 'dart:io';

import 'package:calendar_app/core/database/app_database.dart';
import 'package:calendar_app/core/services/app_services.dart';
import 'package:calendar_app/core/services/export_service.dart';
import 'package:calendar_app/data/datasources/sqlite_repositories.dart';
import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/category.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/categories/providers/categories_provider.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/settings/providers/settings_provider.dart';
import 'package:calendar_app/features/settings/services/backup_controller.dart';
import 'package:calendar_app/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

void main() {
  sqfliteFfiInit();

  group('database persistence', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('calendar_test');
      path = p.join(dir.path, 'calendar.db');
    });

    tearDown(() async {
      await databaseFactoryFfi.deleteDatabase(path);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<Database> open() =>
        AppDatabase.open(factory: databaseFactoryFfi, path: path);

    test('a new database is seeded with the default categories', () async {
      final db = await open();
      final categories = await SqliteCategoryRepository(db).getAll();
      expect(categories.map((c) => c.name),
          containsAll(['Work', 'Personal', 'Family', 'Birthday', 'Other']));
      expect(categories.length, Category.defaults.length);
      await db.close();
    });

    test('events, tasks and settings survive closing and reopening', () async {
      final event = makeEvent(
        title: 'Standup',
        location: 'Office',
        description: 'Daily sync',
        categoryId: 'cat_work',
        reminders: [0, 15],
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: 2,
          weekdays: const {DateTime.monday, DateTime.thursday},
          until: DateTime(2027, 6, 30),
        ),
        exDates: [DateTime(2026, 12, 7, 9)],
      ).copyWith(priority: Priority.high, colorValue: () => 0xFF112233);
      final allDay = makeEvent(
          id: 'e2',
          title: 'Trip',
          start: DateTime(2026, 12, 24),
          end: DateTime(2026, 12, 27),
          allDay: true);
      final task = makeTask(
          due: DateTime(2026, 11, 25, 17, 30), hasDueTime: true, reminderMinutes: 60);

      var db = await open();
      await SqliteEventRepository(db).upsertAll([event, allDay]);
      await SqliteTaskRepository(db).upsert(task);
      await SqliteSettingsRepository(db).save(const AppSettings(
        themeMode: ThemeMode.dark,
        firstDayOfWeek: DateTime.sunday,
        use24Hour: true,
        defaultReminderMinutes: null,
        defaultView: CalendarViewType.week,
      ));
      await db.close();

      // "Restart the app".
      db = await open();
      final boot = await AppBootstrap.load(database: db);

      final loaded = boot.events.firstWhere((e) => e.id == 'e1');
      expect(loaded.title, 'Standup');
      expect(loaded.start, event.start);
      expect(loaded.end, event.end);
      expect(loaded.location, 'Office');
      expect(loaded.description, 'Daily sync');
      expect(loaded.categoryId, 'cat_work');
      expect(loaded.reminders, [0, 15]);
      expect(loaded.recurrence, event.recurrence);
      expect(loaded.exDates, [DateTime(2026, 12, 7, 9)]);
      expect(loaded.priority, Priority.high);
      expect(loaded.colorValue, 0xFF112233);

      final trip = boot.events.firstWhere((e) => e.id == 'e2');
      expect(trip.allDay, isTrue);
      expect(trip.start, DateTime(2026, 12, 24));
      expect(trip.end, DateTime(2026, 12, 27));

      expect(boot.tasks.single.dueDate, DateTime(2026, 11, 25, 17, 30));
      expect(boot.tasks.single.reminderMinutes, 60);

      expect(boot.settings.themeMode, ThemeMode.dark);
      expect(boot.settings.firstDayOfWeek, DateTime.sunday);
      expect(boot.settings.use24Hour, isTrue);
      expect(boot.settings.defaultReminderMinutes, isNull);
      expect(boot.settings.defaultView, CalendarViewType.week);
      await db.close();
    });

    test('edits and deletes are persisted', () async {
      final db = await open();
      final repo = SqliteEventRepository(db);
      await repo.upsert(makeEvent());
      await repo.upsert(makeEvent(title: 'Changed'));
      expect((await repo.getAll()).single.title, 'Changed');
      await repo.delete('e1');
      expect(await repo.getAll(), isEmpty);
      await db.close();
    });

    test('deleting a category keeps its events and tasks, uncategorised',
        () async {
      final db = await open();
      await SqliteEventRepository(db).upsert(makeEvent(categoryId: 'cat_work'));
      await SqliteTaskRepository(db).upsert(makeTask(categoryId: 'cat_work'));
      await SqliteCategoryRepository(db).delete('cat_work');

      expect((await SqliteEventRepository(db).getAll()).single.categoryId, isNull);
      expect((await SqliteTaskRepository(db).getAll()).single.categoryId, isNull);
      expect(
        (await SqliteCategoryRepository(db).getAll()).any((c) => c.id == 'cat_work'),
        isFalse,
      );
      await db.close();
    });
  });

  group('categories', () {
    test('create, rename and delete', () async {
      final c = makeContainer(
        bootstrap: memoryBootstrap(events: [makeEvent(categoryId: 'cat_work')]),
      );
      final categories = c.read(categoriesProvider.notifier);

      await categories.save(const Category(
          id: 'gym', name: 'Gym', colorValue: 0xFF00AA00, icon: 'sports'));
      expect(c.read(categoryMapProvider)['gym']!.name, 'Gym');

      await categories
          .save(c.read(categoryMapProvider)['gym']!.copyWith(name: 'Fitness'));
      expect(c.read(categoryMapProvider)['gym']!.name, 'Fitness');
      expect(c.read(categoryMapProvider)['gym']!.icon, 'sports');

      await categories.delete('gym');
      expect(c.read(categoryMapProvider).containsKey('gym'), isFalse);
    });
  });

  group('import and export', () {
    final events = [
      makeEvent(
        title: 'Lunch, with "Sam"',
        location: 'Cafe; Main St',
        description: 'Line one\nLine two',
        categoryId: 'cat_personal',
        reminders: [15],
        recurrence: RecurrenceRule.weekly,
        exDates: [DateTime(2026, 11, 30, 9)],
      ),
      makeEvent(
          id: 'e2',
          title: 'Holiday',
          start: DateTime(2026, 12, 25),
          allDay: true),
    ];
    final tasks = [
      makeTask(due: DateTime(2026, 11, 25), reminderMinutes: 0),
    ];
    final categories = {for (final c in Category.defaults) c.id: c};

    test('JSON backup round-trips everything', () {
      final json = ExportService.toJson(BackupData(
        events: events,
        tasks: tasks,
        categories: Category.defaults,
        settings: const AppSettings(use24Hour: true),
      ));
      final back = ExportService.fromJson(json);

      expect(back.events.length, 2);
      final e = back.events.first;
      expect(e.title, 'Lunch, with "Sam"');
      expect(e.start, events.first.start);
      expect(e.recurrence, RecurrenceRule.weekly);
      expect(e.exDates, [DateTime(2026, 11, 30, 9)]);
      expect(e.reminders, [15]);
      expect(back.events.last.allDay, isTrue);
      expect(back.events.last.start, DateTime(2026, 12, 25));
      expect(back.tasks.single.title, 'Buy milk');
      expect(back.categories.length, Category.defaults.length);
      expect(back.settings!.use24Hour, isTrue);
    });

    test('rejects files that are not backups', () {
      expect(() => ExportService.fromJson('not json'),
          throwsA(isA<BackupFormatException>()));
      expect(() => ExportService.fromJson('{"hello": 1}'),
          throwsA(isA<BackupFormatException>()));
      expect(
        () => ExportService.fromJson(
            '{"format":"calendar_app_backup","version":999}'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => ExportService.fromJson(
            '{"format":"calendar_app_backup","version":1,"events":[{"bad":1}]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('CSV quotes commas, quotes and line breaks', () {
      final csv = ExportService.eventsToCsv(events, categories);
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('Title,Start,End,All day,Location'));
      expect(csv, contains('"Lunch, with ""Sam"""'));
      expect(csv, contains('2026-11-23 09:00'));
      expect(csv, contains('Personal'));
      expect(csv, contains('"Line one\nLine two"'));
      expect(csv, contains('Holiday,2026-12-25,2026-12-25,Yes'));
    });

    test('CSV neutralises spreadsheet formulas', () {
      final csv = ExportService.eventsToCsv(
          [makeEvent(title: '=HYPERLINK("x")')], categories);
      expect(csv, contains("'=HYPERLINK"));
    });

    test('ICS contains events, recurrence, alarms and tasks', () {
      final ics = ExportService.toIcs(events, categories, tasks: tasks);
      expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0'));
      expect(ics.trim(), endsWith('END:VCALENDAR'));
      expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
      expect(ics, contains('SUMMARY:Lunch\\, with "Sam"'));
      expect(ics, contains('LOCATION:Cafe\\; Main St'));
      expect(ics, contains('DESCRIPTION:Line one\\nLine two'));
      expect(ics, contains('RRULE:FREQ=WEEKLY'));
      expect(ics, contains('DTSTART:20261123T090000'));
      expect(ics, contains('EXDATE:20261130T090000'));
      expect(ics, contains('TRIGGER:-PT15M'));
      expect(ics, contains('CATEGORIES:Personal'));
      // All-day events use dates with an exclusive end.
      expect(ics, contains('DTSTART;VALUE=DATE:20261225'));
      expect(ics, contains('DTEND;VALUE=DATE:20261226'));
      expect(ics, contains('BEGIN:VTODO'));
      expect(ics, contains('DUE;VALUE=DATE:20261125'));
      // No line is longer than 75 octets.
      expect(ics.split('\r\n').every((l) => l.length <= 75), isTrue);
    });

    test('merge keeps existing data and adds the backup', () async {
      final backup = makeContainer(
        bootstrap: memoryBootstrap(events: [makeEvent(id: 'old', title: 'Old')]),
      ).read(backupControllerProvider).exportJson();

      final c = makeContainer(
        bootstrap: memoryBootstrap(events: [makeEvent(id: 'new', title: 'New')]),
      );
      final summary = await c
          .read(backupControllerProvider)
          .importJson(backup, ImportMode.merge);

      expect(summary.events, 1);
      expect(c.read(eventsProvider).map((e) => e.title),
          unorderedEquals(['Old', 'New']));
    });

    test('replace swaps the data for the backup', () async {
      final backup = makeContainer(
        bootstrap: memoryBootstrap(
          events: [makeEvent(id: 'old', title: 'Old')],
          tasks: [makeTask(title: 'Old task')],
          settings: const AppSettings(use24Hour: true),
        ),
      ).read(backupControllerProvider).exportJson();

      final c = makeContainer(
        bootstrap: memoryBootstrap(
          events: [makeEvent(id: 'new', title: 'New')],
          tasks: [makeTask(id: 't9', title: 'New task')],
        ),
      );
      await c.read(backupControllerProvider).importJson(backup, ImportMode.replace);

      expect(c.read(eventsProvider).single.title, 'Old');
      expect(c.read(tasksProvider).single.title, 'Old task');
      expect(c.read(settingsProvider).use24Hour, isTrue);
    });

    test('a bad file never touches existing data, even in replace mode',
        () async {
      final bootstrap = memoryBootstrap(events: [makeEvent()]);
      final c = makeContainer(bootstrap: bootstrap);

      await expectLater(
        c.read(backupControllerProvider).importJson('{broken', ImportMode.replace),
        throwsA(isA<BackupFormatException>()),
      );
      expect(c.read(eventsProvider), hasLength(1));
      expect(await bootstrap.eventRepository.getAll(), hasLength(1));
    });

    test('exporting does not change stored data', () async {
      final bootstrap = memoryBootstrap(events: events, tasks: tasks);
      final c = makeContainer(bootstrap: bootstrap);
      final controller = c.read(backupControllerProvider);
      controller.exportJson();
      controller.exportCsv();
      controller.exportIcs();
      expect(await bootstrap.eventRepository.getAll(), hasLength(2));
      expect(await bootstrap.taskRepository.getAll(), hasLength(1));
    });

    test('erase removes events and tasks and restores default categories',
        () async {
      final c = makeContainer(
        bootstrap: memoryBootstrap(
          events: events,
          tasks: tasks,
          categories: const [Category(id: 'x', name: 'Mine', colorValue: 1)],
        ),
      );
      await c.read(backupControllerProvider).eraseAll();
      expect(c.read(eventsProvider), isEmpty);
      expect(c.read(tasksProvider), isEmpty);
      expect(c.read(categoriesProvider).length, Category.defaults.length);
    });
  });
}
