import 'package:calendar_app/core/notifications/notification_service.dart';
import 'package:calendar_app/core/notifications/reminder_planner.dart';
import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/events/services/series_editor.dart';
import 'package:calendar_app/features/settings/providers/settings_provider.dart';
import 'package:calendar_app/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const settings = AppSettings(use24Hour: true);

  group('reminder planning', () {
    test('schedules each reminder before the event start', () {
      final e = makeEvent(
          start: DateTime(2026, 11, 23, 15), reminders: [0, 15, 60], location: 'HQ');
      final plan = ReminderPlanner.plan(
          events: [e], tasks: [], settings: settings, now: testNow);
      expect(plan.map((r) => r.when), [
        DateTime(2026, 11, 23, 14),
        DateTime(2026, 11, 23, 14, 45),
        DateTime(2026, 11, 23, 15),
      ]);
      expect(plan.first.title, 'Meeting');
      expect(plan.first.body, contains('15:00'));
      expect(plan.first.body, contains('HQ'));
    });

    test('never includes the description or notes', () {
      final e = makeEvent(
        start: DateTime(2026, 11, 23, 15),
        reminders: [10],
        description: 'SECRET-DESCRIPTION',
        notes: 'SECRET-NOTES',
      );
      final r = ReminderPlanner.plan(
              events: [e], tasks: [], settings: settings, now: testNow)
          .single;
      expect('${r.title} ${r.body}', isNot(contains('SECRET')));
    });

    test('skips reminders that are already in the past', () {
      final e = makeEvent(start: DateTime(2026, 11, 23, 10, 5), reminders: [15]);
      expect(
        ReminderPlanner.plan(
            events: [e], tasks: [], settings: settings, now: testNow),
        isEmpty,
      );
    });

    test('plans nothing when notifications are disabled', () {
      final e = makeEvent(start: DateTime(2026, 11, 24, 9), reminders: [15]);
      expect(
        ReminderPlanner.plan(
          events: [e],
          tasks: [],
          settings: const AppSettings(notificationsEnabled: false),
          now: testNow,
        ),
        isEmpty,
      );
    });

    test('covers upcoming occurrences of recurring events, within the cap',
        () {
      final e = makeEvent(
        start: DateTime(2026, 1, 1, 8),
        reminders: [30],
        recurrence: RecurrenceRule.daily,
      );
      final plan = ReminderPlanner.plan(
          events: [e], tasks: [], settings: settings, now: testNow);
      expect(plan.length, ReminderPlanner.maxScheduled);
      expect(plan.first.when, DateTime(2026, 11, 24, 7, 30));
      expect(plan.map((r) => r.id).toSet().length, plan.length);
    });

    test('all-day reminders are measured from 9:00', () {
      final e = makeEvent(
          start: DateTime(2026, 11, 25), allDay: true, reminders: [1440]);
      final r = ReminderPlanner.plan(
              events: [e], tasks: [], settings: settings, now: testNow)
          .single;
      expect(r.when, DateTime(2026, 11, 24, 9));
    });

    test('tasks get reminders until they are completed', () {
      final due = DateTime(2026, 11, 24, 12);
      final open = makeTask(due: due, hasDueTime: true, reminderMinutes: 60);
      final done = makeTask(
          id: 't2', due: due, hasDueTime: true, reminderMinutes: 60, completed: true);
      final plan = ReminderPlanner.plan(
          events: [], tasks: [open, done], settings: settings, now: testNow);
      expect(plan.single.when, DateTime(2026, 11, 24, 11));
      expect(NotificationTarget.decode(plan.single.payload)!.isTask, isTrue);
    });

    test('ids are stable and payloads round-trip to a route', () {
      expect(ReminderPlanner.stableId('abc'), ReminderPlanner.stableId('abc'));
      expect(ReminderPlanner.stableId('abc'), isNot(ReminderPlanner.stableId('abd')));
      expect(ReminderPlanner.stableId('abc'), greaterThanOrEqualTo(0));

      final occ = DateTime(2026, 11, 30, 9);
      final target =
          NotificationTarget.decode(NotificationTarget.event('e1', occ).encode())!;
      expect(target.id, 'e1');
      expect(target.occurrenceStart, occ);
      expect(target.route, '/event/e1?occ=${occ.millisecondsSinceEpoch}');
      expect(NotificationTarget.decode('task|t9')!.route, '/task/t9');
      expect(NotificationTarget.decode('garbage'), isNull);
      expect(NotificationTarget.decode(null), isNull);
    });
  });

  group('scheduling follows the data', () {
    test('saving an event schedules its reminder', () async {
      final fake = FakeNotificationService();
      final c = makeContainer(notifications: fake);
      await c.read(eventsProvider.notifier).save(
          makeEvent(start: DateTime(2026, 11, 24, 9), reminders: [15]));
      expect(fake.scheduled.single.when, DateTime(2026, 11, 24, 8, 45));
    });

    test('rescheduling an event moves its notification', () async {
      final fake = FakeNotificationService();
      final e = makeEvent(start: DateTime(2026, 11, 24, 9), reminders: [15]);
      final c = makeContainer(
          bootstrap: memoryBootstrap(events: [e]), notifications: fake);
      final events = c.read(eventsProvider.notifier);
      await events.editOccurrence(
        master: e,
        occurrenceStart: e.start,
        edited: e.copyWith(
            start: DateTime(2026, 11, 26, 13), end: DateTime(2026, 11, 26, 14)),
        scope: RecurrenceScope.all,
      );
      expect(fake.scheduled.single.when, DateTime(2026, 11, 26, 12, 45));
    });

    test('deleting an event cancels its notification', () async {
      final fake = FakeNotificationService();
      final e = makeEvent(start: DateTime(2026, 11, 24, 9), reminders: [15]);
      final c = makeContainer(
          bootstrap: memoryBootstrap(events: [e]), notifications: fake);
      final events = c.read(eventsProvider.notifier);
      await events.save(e);
      expect(fake.scheduled, hasLength(1));

      await events.deleteOccurrence(
          master: e, occurrenceStart: e.start, scope: RecurrenceScope.all);
      expect(fake.scheduled, isEmpty);
      expect(fake.cancelAllCalls, greaterThanOrEqualTo(2));
    });

    test('turning notifications off cancels everything', () async {
      final fake = FakeNotificationService();
      final c = makeContainer(notifications: fake);
      await c.read(eventsProvider.notifier).save(
          makeEvent(start: DateTime(2026, 11, 24, 9), reminders: [15]));
      expect(fake.scheduled, hasLength(1));

      await c
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(notificationsEnabled: false));
      expect(fake.scheduled, isEmpty);
    });

    test('completing a task cancels its reminder', () async {
      final fake = FakeNotificationService();
      final c = makeContainer(notifications: fake);
      final task = makeTask(
          due: DateTime(2026, 11, 24, 12), hasDueTime: true, reminderMinutes: 30);
      final tasks = c.read(tasksProvider.notifier);
      await tasks.save(task);
      expect(fake.scheduled, hasLength(1));

      await tasks.setCompleted(task, true);
      expect(fake.scheduled, isEmpty);
    });
  });
}
