import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/category.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/calendar/providers/calendar_data.dart';
import 'package:calendar_app/features/search/services/search_service.dart';
import 'package:calendar_app/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('task management', () {
    test('create, complete, reopen and delete', () async {
      final bootstrap = memoryBootstrap();
      final c = makeContainer(bootstrap: bootstrap);
      final tasks = c.read(tasksProvider.notifier);

      await tasks.save(makeTask());
      expect(c.read(tasksProvider).single.completed, isFalse);

      await tasks.setCompleted(c.read(tasksProvider).single, true);
      expect(c.read(tasksProvider).single.completed, isTrue);
      expect(c.read(tasksProvider).single.completedAt, testNow);
      expect((await bootstrap.taskRepository.getAll()).single.completed, isTrue);

      await tasks.setCompleted(c.read(tasksProvider).single, false);
      expect(c.read(tasksProvider).single.completedAt, isNull);

      await tasks.delete('t1');
      expect(c.read(tasksProvider), isEmpty);
      expect(await bootstrap.taskRepository.getAll(), isEmpty);
    });

    test('overdue takes the due time into account', () {
      final timed = makeTask(due: DateTime(2026, 11, 23, 9), hasDueTime: true);
      final dateOnly = makeTask(due: DateTime(2026, 11, 23));
      expect(timed.isOverdue(testNow), isTrue);
      // A task due "today" is not overdue until the day is over.
      expect(dateOnly.isOverdue(testNow), isFalse);
      expect(dateOnly.isOverdue(DateTime(2026, 11, 24, 0, 1)), isTrue);
      expect(timed.copyWith(completed: true).isOverdue(testNow), isFalse);
    });

    test('sorting puts open tasks first, by due date then priority', () {
      final list = [
        makeTask(id: 'done', title: 'Done', completed: true, due: DateTime(2026, 1, 1)),
        makeTask(id: 'none', title: 'No date'),
        makeTask(id: 'late', title: 'Later', due: DateTime(2026, 12, 1)),
        makeTask(id: 'soon', title: 'Soon', due: DateTime(2026, 11, 24)),
        makeTask(id: 'soonHigh', title: 'Soon high', due: DateTime(2026, 11, 24))
            .copyWith(priority: Priority.high),
      ]..sort(compareTasks);
      expect(list.map((t) => t.id), ['soonHigh', 'soon', 'late', 'none', 'done']);
    });

    test('dated tasks appear in the calendar according to settings', () {
      final tasks = [
        makeTask(id: 'a', due: DateTime(2026, 11, 24)),
        makeTask(id: 'b', due: DateTime(2026, 11, 24), completed: true),
        makeTask(id: 'c'),
      ];

      var c = makeContainer(bootstrap: memoryBootstrap(tasks: tasks));
      expect(c.read(calendarTasksProvider).map((t) => t.id), ['a', 'b']);

      c = makeContainer(
        bootstrap: memoryBootstrap(
            tasks: tasks, settings: const AppSettings(showCompletedTasks: false)),
      );
      expect(c.read(calendarTasksProvider).map((t) => t.id), ['a']);

      c = makeContainer(
        bootstrap: memoryBootstrap(
            tasks: tasks, settings: const AppSettings(showTasksInCalendar: false)),
      );
      expect(c.read(calendarTasksProvider), isEmpty);
    });

    test('a calendar range indexes events and tasks by day', () {
      final range = CalendarRange(
        from: DateTime(2026, 11, 23),
        to: DateTime(2026, 11, 30),
        events: [
          makeEvent(),
          makeEvent(
              id: 'trip',
              start: DateTime(2026, 11, 25),
              end: DateTime(2026, 11, 27),
              allDay: true),
        ],
        tasks: [makeTask(due: DateTime(2026, 11, 26, 8), hasDueTime: true)],
      );
      expect(range.occurrencesOn(DateTime(2026, 11, 23)).single.event.id, 'e1');
      expect(range.occurrencesOn(DateTime(2026, 11, 26)).single.event.id, 'trip');
      expect(range.tasksOn(DateTime(2026, 11, 26)), hasLength(1));
      expect(range.hasItems(DateTime(2026, 11, 24)), isFalse);
      expect(range.hasItems(DateTime(2026, 11, 27)), isTrue);
      expect(range.hasItems(DateTime(2026, 11, 28)), isFalse);
    });
  });

  group('search', () {
    final categories = {for (final c in Category.defaults) c.id: c};
    final events = [
      makeEvent(id: 'a', title: 'Team standup', location: 'Zoom'),
      makeEvent(
          id: 'b',
          title: 'Dinner',
          location: 'Luigi\'s Trattoria',
          description: 'Anniversary booking',
          start: DateTime(2026, 11, 28, 19)),
      makeEvent(id: 'c', title: 'Checkup', categoryId: 'cat_health'),
      makeEvent(
          id: 'd',
          title: 'Yoga',
          start: DateTime(2026, 1, 5, 7),
          recurrence: RecurrenceRule.weekly),
      makeEvent(id: 'old', title: 'Old dinner', start: DateTime(2025, 3, 1, 19)),
    ];
    final tasks = [
      makeTask(title: 'Book dinner table'),
      makeTask(id: 't2', title: 'Renew passport', description: 'Bring photos'),
    ];

    SearchResults run(String q) => SearchService.search(
          query: q,
          events: events,
          tasks: tasks,
          categories: categories,
          now: testNow,
        );

    test('matches titles, case-insensitively', () {
      expect(run('STANDUP').events.single.event.id, 'a');
    });

    test('matches descriptions', () {
      expect(run('anniversary').events.single.event.id, 'b');
    });

    test('matches locations', () {
      expect(run('trattoria').events.single.event.id, 'b');
      expect(run('zoom').events.single.event.id, 'a');
    });

    test('matches category names', () {
      expect(run('health').events.single.event.id, 'c');
    });

    test('requires every word to match', () {
      expect(run('dinner luigi').events.single.event.id, 'b');
      expect(run('dinner zoom').events, isEmpty);
    });

    test('lists upcoming results before past ones', () {
      expect(run('dinner').events.map((o) => o.event.id), ['b', 'old']);
    });

    test('finds tasks too', () {
      expect(run('dinner').tasks.single.title, 'Book dinner table');
      expect(run('photos').tasks.single.id, 't2');
    });

    test('a recurring event is listed once, at its next occurrence', () {
      final result = run('yoga').events.single;
      expect(result.start, DateTime(2026, 11, 30, 7));
    });

    test('an empty query returns nothing', () {
      expect(run('   ').isEmpty, isTrue);
      expect(run('zzz').isEmpty, isTrue);
    });
  });
}
