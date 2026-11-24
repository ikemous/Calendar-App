import 'dart:io';

import 'package:calendar_app/core/database/app_database.dart';
import 'package:calendar_app/core/services/app_services.dart';
import 'package:calendar_app/data/datasources/sqlite_repositories.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/calendar/services/recurrence_engine.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/events/services/series_editor.dart';
import 'package:calendar_app/features/settings/services/backup_controller.dart';
import 'package:calendar_app/features/sync/providers/sync_controller.dart';
import 'package:calendar_app/features/sync/services/google_event_mapper.dart';
import 'package:calendar_app/features/sync/services/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';
import '../sync_fakes.dart';

/// A Google-style timed event.
Map<String, dynamic> remoteEvent(
  String summary,
  DateTime start, {
  Duration length = const Duration(hours: 1),
  List<String>? recurrence,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'summary': summary,
      'start': {'dateTime': start.toUtc().toIso8601String()},
      'end': {'dateTime': start.add(length).toUtc().toIso8601String()},
      'recurrence': ?recurrence,
      ...extra,
    };

void main() {
  late FakeGoogleCalendar google;
  late MemoryEventRepository events;
  late MemorySyncStateRepository state;
  late DateTime clock;

  SyncEngine engine() => SyncEngine(
        events: events,
        state: state,
        api: google,
        timeZone: 'Etc/UTC',
        now: () => clock,
      );

  CalendarEvent local(String title) =>
      events.items.values.firstWhere((e) => e.title == title);

  /// Simulates the user editing an event in the app at [clock].
  Future<void> editLocally(CalendarEvent e) =>
      events.upsert(e.copyWith(updatedAt: clock));

  void tick([Duration by = const Duration(minutes: 1)]) {
    clock = clock.add(by);
    google.clock = clock;
  }

  setUp(() {
    google = FakeGoogleCalendar();
    events = MemoryEventRepository();
    state = MemorySyncStateRepository();
    clock = testNow;
  });

  group('first sync', () {
    test('uploads local events and downloads Google events', () async {
      await events.upsert(makeEvent(title: 'Local lunch', location: 'Cafe'));
      google.remoteAdd(remoteEvent('Google standup', DateTime(2026, 11, 24, 9),
          extra: {'location': 'Zoom', 'description': 'Daily'}));

      final result = await engine().sync();

      expect(result.pushed, 1);
      expect(result.pulled, 1);
      // Local event now exists in Google...
      expect(google.bySummary('Local lunch')['location'], 'Cafe');
      expect(local('Local lunch').remoteId, isNotNull);
      expect(local('Local lunch').needsSync, isFalse);
      // ...and the Google event exists locally.
      final pulled = local('Google standup');
      expect(pulled.start, DateTime(2026, 11, 24, 9));
      expect(pulled.end, DateTime(2026, 11, 24, 10));
      expect(pulled.location, 'Zoom');
      expect(pulled.description, 'Daily');
      expect(pulled.needsSync, isFalse);
    });

    test('a second sync with no changes does nothing', () async {
      await events.upsert(makeEvent());
      google.remoteAdd(remoteEvent('Remote', DateTime(2026, 11, 24, 9)));
      await engine().sync();
      final inserts = google.inserts;

      final again = await engine().sync();

      expect(again.pulled, 0);
      expect(again.pushed, 0);
      expect(google.inserts, inserts);
      expect(google.patches, 0);
      expect(events.items.length, 2);
      expect(google.live.length, 2);
    });

    test('reads every page of a long listing', () async {
      google = FakeGoogleCalendar(pageSize: 3);
      for (var i = 0; i < 8; i++) {
        google.remoteAdd(remoteEvent('Event $i', DateTime(2026, 12, 1 + i, 9)));
      }
      final result = await engine().sync();
      expect(result.pulled, 8);
      expect(events.items.length, 8);
    });
  });

  group('changes made in the app', () {
    test('an edit is sent to Google', () async {
      await events.upsert(makeEvent(title: 'Dentist'));
      await engine().sync();

      tick();
      await editLocally(local('Dentist').copyWith(
          title: 'Dentist (moved)', start: DateTime(2026, 11, 25, 14),
          end: DateTime(2026, 11, 25, 15)));
      final result = await engine().sync();

      expect(result.pushed, 1);
      expect(google.patches, 1);
      expect(google.inserts, 1);
      final remote = google.bySummary('Dentist (moved)');
      expect(DateTime.parse(remote['start']['dateTime'] as String).toLocal(),
          DateTime(2026, 11, 25, 14));
    });

    test('a deletion is sent to Google', () async {
      final container = makeContainer(google: google, auth: FakeCalendarAuth());
      final notifier = container.read(eventsProvider.notifier);
      await container.read(syncControllerProvider.notifier).connect();
      await notifier.save(makeEvent(title: 'Doomed'));
      await container.read(syncControllerProvider.notifier).syncNow();
      expect(google.live.single['summary'], 'Doomed');

      final event = container.read(eventsProvider).single;
      await notifier.deleteOccurrence(
          master: event, occurrenceStart: event.start, scope: RecurrenceScope.all);
      await container.read(syncControllerProvider.notifier).syncNow();

      expect(google.live, isEmpty);
      expect(google.deletes, 1);
    });

    test('notes, priority, colour and category survive a round trip',
        () async {
      await events.upsert(makeEvent(title: 'Rich', notes: 'Bring ID', categoryId: 'cat_work')
          .copyWith(priority: Priority.high, colorValue: () => 0xFF112233));
      await engine().sync();

      // A fresh install connecting to the same account.
      events = MemoryEventRepository();
      state = MemorySyncStateRepository();
      await engine().sync();

      final copy = local('Rich');
      expect(copy.notes, 'Bring ID');
      expect(copy.priority, Priority.high);
      expect(copy.colorValue, 0xFF112233);
      expect(copy.categoryId, 'cat_work');
    });

    test('reminders are sent as popup overrides', () async {
      await events.upsert(makeEvent(reminders: [0, 15, 1440]));
      await engine().sync();
      expect(google.live.single['reminders'], {
        'useDefault': false,
        'overrides': [
          {'method': 'popup', 'minutes': 0},
          {'method': 'popup', 'minutes': 15},
          {'method': 'popup', 'minutes': 1440},
        ],
      });
    });
  });

  group('changes made in Google', () {
    test('an edit updates the local event and keeps its id', () async {
      await events.upsert(makeEvent(title: 'Review', notes: 'Private notes'));
      await engine().sync();
      final before = local('Review');

      tick();
      google.remoteEdit(before.remoteId!, {
        'summary': 'Review (rescheduled)',
        'start': {'dateTime': DateTime(2026, 11, 26, 16).toUtc().toIso8601String()},
        'end': {'dateTime': DateTime(2026, 11, 26, 17).toUtc().toIso8601String()},
      });
      final result = await engine().sync();

      expect(result.pulled, 1);
      final after = local('Review (rescheduled)');
      expect(after.id, before.id);
      expect(after.start, DateTime(2026, 11, 26, 16));
      expect(after.notes, 'Private notes');
      expect(after.needsSync, isFalse);
      expect(google.patches, 0);
    });

    test('a deletion removes the local event', () async {
      await events.upsert(makeEvent(title: 'Cancelled meeting'));
      await engine().sync();

      tick();
      google.remoteDelete(local('Cancelled meeting').remoteId!);
      final result = await engine().sync();

      expect(result.removedLocally, 1);
      expect(events.items, isEmpty);
    });

    test('calendar default reminders apply to events that use them', () async {
      google.defaultReminders = [10];
      google.remoteAdd(remoteEvent('Defaults', DateTime(2026, 11, 24, 9),
          extra: {'reminders': {'useDefault': true}}));
      google.remoteAdd(remoteEvent('Custom', DateTime(2026, 11, 24, 11), extra: {
        'reminders': {
          'useDefault': false,
          'overrides': [
            {'method': 'popup', 'minutes': 45},
            {'method': 'email', 'minutes': 5},
          ],
        },
      }));
      await engine().sync();
      expect(local('Defaults').reminders, [10]);
      expect(local('Custom').reminders, [5, 45]);
    });

    test('all-day events convert between exclusive and inclusive ends',
        () async {
      google.remoteAdd({
        'summary': 'Trip',
        'start': {'date': '2026-12-24'},
        'end': {'date': '2026-12-27'},
      });
      await events.upsert(makeEvent(
          title: 'Offsite',
          start: DateTime(2026, 12, 1),
          end: DateTime(2026, 12, 2),
          allDay: true));
      await engine().sync();

      final trip = local('Trip');
      expect(trip.allDay, isTrue);
      expect(trip.start, DateTime(2026, 12, 24));
      expect(trip.end, DateTime(2026, 12, 26));

      final offsite = google.bySummary('Offsite');
      expect(offsite['start'], {'date': '2026-12-01'});
      expect(offsite['end'], {'date': '2026-12-03'});
    });
  });

  group('conflicts', () {
    test('the more recent change wins: local newer', () async {
      await events.upsert(makeEvent(title: 'Plan'));
      await engine().sync();
      final id = local('Plan').remoteId!;

      tick();
      google.remoteEdit(id, {'summary': 'Plan (Google)'});
      tick();
      await editLocally(local('Plan').copyWith(title: 'Plan (app)'));
      await engine().sync();

      expect(events.items.values.single.title, 'Plan (app)');
      expect(google.items[id]!['summary'], 'Plan (app)');
    });

    test('the more recent change wins: Google newer', () async {
      await events.upsert(makeEvent(title: 'Plan'));
      await engine().sync();
      final id = local('Plan').remoteId!;

      tick();
      await editLocally(local('Plan').copyWith(title: 'Plan (app)'));
      tick();
      google.remoteEdit(id, {'summary': 'Plan (Google)'});
      await engine().sync();

      expect(events.items.values.single.title, 'Plan (Google)');
      expect(google.items[id]!['summary'], 'Plan (Google)');
    });

    test('an event deleted in Google but edited here later is recreated',
        () async {
      await events.upsert(makeEvent(title: 'Keep me'));
      await engine().sync();
      final oldId = local('Keep me').remoteId!;

      // Deleted remotely, but the tombstone is missed (expired token) and
      // the event was edited locally afterwards.
      tick();
      google.remoteDelete(oldId);
      tick();
      await editLocally(local('Keep me').copyWith(location: 'Room 1'));
      await state.write(SyncKeys.syncToken, null);
      await engine().sync();

      expect(google.live.single['summary'], 'Keep me');
      expect(local('Keep me').remoteId, isNot(oldId));
    });
  });

  group('recurring events', () {
    test('a local series is sent with its rule and excluded dates', () async {
      await events.upsert(makeEvent(
        title: 'Yoga',
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: 2,
          weekdays: const {DateTime.monday, DateTime.thursday},
          until: DateTime(2027, 3, 31),
        ),
        exDates: [DateTime(2026, 12, 7, 9)],
      ));
      await engine().sync();

      final remote = google.bySummary('Yoga');
      expect(remote['recurrence'], [
        'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;'
            'UNTIL=${_stamp(DateTime(2027, 3, 31, 23, 59, 59))}',
        'EXDATE:${_stamp(DateTime(2026, 12, 7, 9))}',
      ]);
      expect(remote['start']['timeZone'], 'Etc/UTC');
    });

    test('a Google series arrives with the same occurrences', () async {
      google.remoteAdd(remoteEvent('Team sync', DateTime(2026, 11, 23, 10),
          recurrence: [
            'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6',
            'EXDATE:${_stamp(DateTime(2026, 11, 25, 10))}',
          ]));
      await engine().sync();

      final starts = RecurrenceEngine.expand(
              local('Team sync'), DateTime(2026, 11), DateTime(2027))
          .map((o) => o.start);
      expect(starts, [
        DateTime(2026, 11, 23, 10),
        DateTime(2026, 11, 30, 10),
        DateTime(2026, 12, 2, 10),
        DateTime(2026, 12, 7, 10),
        DateTime(2026, 12, 9, 10),
      ]);
    });

    test('"monthly on the second Tuesday" is understood', () async {
      google.remoteAdd(remoteEvent('Board', DateTime(2026, 11, 10, 18),
          recurrence: ['RRULE:FREQ=MONTHLY;BYDAY=2TU']));
      google.remoteAdd(remoteEvent('Payday', DateTime(2026, 11, 27, 9),
          recurrence: ['RRULE:FREQ=MONTHLY;BYDAY=-1FR']));
      await engine().sync();

      List<DateTime> next(String title) => RecurrenceEngine.expand(
              local(title), DateTime(2026, 11), DateTime(2027, 3))
          .map((o) => o.start)
          .toList();
      expect(next('Board'), [
        DateTime(2026, 11, 10, 18),
        DateTime(2026, 12, 8, 18),
        DateTime(2027, 1, 12, 18),
        DateTime(2027, 2, 9, 18),
      ]);
      expect(next('Payday'), [
        DateTime(2026, 11, 27, 9),
        DateTime(2026, 12, 25, 9),
        DateTime(2027, 1, 29, 9),
        DateTime(2027, 2, 26, 9),
      ]);
      expect(local('Board').recurrence!.describe(),
          'Monthly on the second Tue');
    });

    test('an unsupported rule is kept as-is and never overwritten', () async {
      const rule = 'RRULE:FREQ=MONTHLY;BYMONTHDAY=1,15';
      final added = google.remoteAdd(remoteEvent(
          'Twice a month', DateTime(2026, 11, 15, 9), recurrence: [rule]));
      final result = await engine().sync();

      expect(result.unsupportedRepeats, 1);
      final event = local('Twice a month');
      expect(event.isRecurring, isFalse);
      expect(event.remoteRecurrence, [rule]);

      // Editing something else locally must not destroy the rule in Google.
      tick();
      await editLocally(event.copyWith(location: 'HQ'));
      await engine().sync();

      final remote = google.items[added['id']]!;
      expect(remote['location'], 'HQ');
      expect(remote['recurrence'], [rule]);
    });

    test('one date deleted in Google is hidden locally', () async {
      final series = google.remoteAdd(remoteEvent(
          'Standup', DateTime(2026, 11, 23, 9),
          recurrence: ['RRULE:FREQ=DAILY']));
      await engine().sync();

      tick();
      google.remoteAdd({
        'recurringEventId': series['id'],
        'originalStartTime': {
          'dateTime': DateTime(2026, 11, 25, 9).toUtc().toIso8601String(),
        },
      }, id: '${series['id']}_x1')['status'] = 'cancelled';
      await engine().sync();

      final master = local('Standup');
      expect(master.exDates, [DateTime(2026, 11, 25, 9)]);
      expect(master.needsSync, isFalse);
    });

    test('one date changed in Google becomes a detached local event',
        () async {
      final series = google.remoteAdd(remoteEvent(
          'Standup', DateTime(2026, 11, 23, 9),
          recurrence: ['RRULE:FREQ=DAILY']));
      await engine().sync();

      tick();
      final instanceId = '${series['id']}_20261125T090000Z';
      google.remoteAdd({
        ...remoteEvent('Standup (late)', DateTime(2026, 11, 25, 11)),
        'recurringEventId': series['id'],
        'originalStartTime': {
          'dateTime': DateTime(2026, 11, 25, 9).toUtc().toIso8601String(),
        },
      }, id: instanceId);
      await engine().sync();

      final master = local('Standup');
      final moved = local('Standup (late)');
      expect(moved.seriesId, master.id);
      expect(moved.originalStart, DateTime(2026, 11, 25, 9));
      expect(moved.isRecurring, isFalse);
      // The calendar shows the moved one instead of the 9:00 occurrence.
      final day = RecurrenceEngine.occurrencesInRange(events.items.values,
              DateTime(2026, 11, 25), DateTime(2026, 11, 26))
          .map((o) => o.start);
      expect(day, [DateTime(2026, 11, 25, 11)]);

      // Editing the series locally must not turn the changed date into an
      // EXDATE, which would delete the modified instance in Google.
      tick();
      await editLocally(master.copyWith(location: 'Room 9'));
      await engine().sync();
      expect(google.items[series['id']]!['recurrence'], ['RRULE:FREQ=DAILY']);
      expect(google.items[instanceId]!['status'], 'confirmed');
    });
  });

  group('robustness', () {
    test('an expired sync token triggers a full listing without duplicates',
        () async {
      await events.upsert(makeEvent(title: 'A'));
      google.remoteAdd(remoteEvent('B', DateTime(2026, 11, 24, 9)));
      await engine().sync();

      tick();
      google.remoteAdd(remoteEvent('C', DateTime(2026, 11, 25, 9)));
      google.expireTokens = true;
      await engine().sync();

      expect(events.items.values.map((e) => e.title),
          unorderedEquals(['A', 'B', 'C']));
      expect(google.live.length, 3);
    });

    test('a failed sync leaves changes queued for the next one', () async {
      await events.upsert(makeEvent(title: 'Offline edit'));
      google.offline = true;
      await expectLater(engine().sync(), throwsException);
      expect(local('Offline edit').needsSync, isTrue);

      google.offline = false;
      await engine().sync();
      expect(google.live.single['summary'], 'Offline edit');
    });

    test('erasing local data never deletes anything from Google', () async {
      final container = makeContainer(google: google, auth: FakeCalendarAuth());
      final sync = container.read(syncControllerProvider.notifier);
      await container
          .read(eventsProvider.notifier)
          .save(makeEvent(title: 'Precious'));
      await sync.connect();
      expect(google.live.single['summary'], 'Precious');

      await container.read(backupControllerProvider).eraseAll();
      expect(container.read(eventsProvider), isEmpty);
      await sync.syncNow();

      expect(google.deletes, 0);
      expect(google.live.single['summary'], 'Precious');
      // The next sync brings the events back from Google.
      expect(container.read(eventsProvider).single.title, 'Precious');
    });
  });

  group('sync controller', () {
    test('connect signs in, syncs and remembers the account', () async {
      final bootstrap = memoryBootstrap(events: [makeEvent(title: 'Mine')]);
      final container = makeContainer(
          bootstrap: bootstrap, google: google, auth: FakeCalendarAuth());
      google.remoteAdd(remoteEvent('Theirs', DateTime(2026, 11, 24, 9)));

      final connected =
          await container.read(syncControllerProvider.notifier).connect();

      expect(connected, isTrue);
      final status = container.read(syncControllerProvider);
      expect(status.account, 'me@example.com');
      expect(status.error, isNull);
      expect(status.lastSync, testNow);
      expect(status.lastResult!.pulled, 1);
      expect(status.lastResult!.pushed, 1);
      expect(container.read(eventsProvider).map((e) => e.title),
          unorderedEquals(['Mine', 'Theirs']));
      expect((await bootstrap.syncStateRepository.readAll())[SyncKeys.account],
          'me@example.com');
    });

    test('cancelling sign-in changes nothing', () async {
      final container = makeContainer(
          google: google, auth: FakeCalendarAuth(email: null));
      expect(await container.read(syncControllerProvider.notifier).connect(),
          isFalse);
      expect(container.read(syncControllerProvider).connected, isFalse);
    });

    test('reminders are scheduled for events that arrive from Google',
        () async {
      final notifications = FakeNotificationService();
      final container = makeContainer(
          google: google, auth: FakeCalendarAuth(), notifications: notifications);
      google.remoteAdd(remoteEvent('Remote', DateTime(2026, 11, 24, 9), extra: {
        'reminders': {
          'useDefault': false,
          'overrides': [{'method': 'popup', 'minutes': 20}],
        },
      }));
      await container.read(syncControllerProvider.notifier).connect();
      expect(notifications.scheduled.single.when, DateTime(2026, 11, 24, 8, 40));
    });

    test('reports a clear error when Google needs a new sign-in', () async {
      final auth = FakeCalendarAuth();
      final container = makeContainer(google: google, auth: auth);
      final sync = container.read(syncControllerProvider.notifier);
      await sync.connect();

      auth.token = null;
      await sync.syncNow();
      expect(container.read(syncControllerProvider).error,
          'Google needs you to sign in again.');

      auth.token = 'token';
      await sync.syncNow();
      expect(container.read(syncControllerProvider).error, isNull);
    });

    test('reports a connection problem and recovers', () async {
      final container = makeContainer(google: google, auth: FakeCalendarAuth());
      final sync = container.read(syncControllerProvider.notifier);
      await sync.connect();
      google.offline = true;
      await sync.syncNow();
      expect(container.read(syncControllerProvider).error,
          contains('internet connection'));
      expect(container.read(syncControllerProvider).connected, isTrue);
    });

    test('disconnecting and reconnecting the same account does not duplicate',
        () async {
      final auth = FakeCalendarAuth();
      final container = makeContainer(
          bootstrap: memoryBootstrap(events: [makeEvent(title: 'Once')]),
          google: google,
          auth: auth);
      final sync = container.read(syncControllerProvider.notifier);
      await sync.connect();
      await sync.disconnect();
      expect(auth.signOuts, 1);
      expect(container.read(syncControllerProvider).connected, isFalse);
      expect(container.read(eventsProvider), hasLength(1));

      await sync.connect();
      expect(container.read(eventsProvider), hasLength(1));
      expect(google.live, hasLength(1));
    });

    test('connecting a different account starts fresh links', () async {
      final auth = FakeCalendarAuth();
      final container = makeContainer(
          bootstrap: memoryBootstrap(events: [makeEvent(title: 'Mine')]),
          google: google,
          auth: auth);
      final sync = container.read(syncControllerProvider.notifier);
      await sync.connect();
      await sync.disconnect();

      // A different person's (empty) calendar.
      final other = FakeGoogleCalendar();
      auth.email = 'other@example.com';
      final container2 = makeContainer(
        bootstrap: AppBootstrap(
          events: container.read(eventsProvider),
          tasks: const [],
          categories: const [],
          settings: container.read(bootstrapProvider).settings,
          eventRepository: container.read(eventRepositoryProvider),
          taskRepository: container.read(taskRepositoryProvider),
          categoryRepository: container.read(categoryRepositoryProvider),
          settingsRepository: container.read(settingsRepositoryProvider),
          syncStateRepository: container.read(syncStateRepositoryProvider),
          syncState: await container.read(syncStateRepositoryProvider).readAll(),
        ),
        google: other,
        auth: auth,
      );
      await container2.read(syncControllerProvider.notifier).connect();

      // The event is uploaded to the new account as a new event.
      expect(other.live.single['summary'], 'Mine');
      expect(other.patches, 0);
    });

    test('nothing syncs while no account is connected', () async {
      final container = makeContainer(google: google, auth: FakeCalendarAuth());
      await container.read(eventsProvider.notifier).save(makeEvent());
      await container.read(syncControllerProvider.notifier).syncNow();
      expect(google.items, isEmpty);
    });
  });

  group('rule parsing', () {
    final start = DateTime(2026, 11, 23, 9); // a Monday

    test('supported rules', () {
      expect(GoogleEventMapper.parseRRule('RRULE:FREQ=DAILY', start),
          RecurrenceRule.daily);
      expect(GoogleEventMapper.parseRRule('RRULE:FREQ=WEEKLY;BYDAY=MO', start),
          RecurrenceRule.weekly);
      expect(
          GoogleEventMapper.parseRRule(
              'RRULE:FREQ=WEEKLY;WKST=SU;INTERVAL=2;BYDAY=MO', start),
          RecurrenceRule.biweekly);
      expect(
          GoogleEventMapper.parseRRule(
              'RRULE:FREQ=MONTHLY;BYMONTHDAY=23', start),
          RecurrenceRule.monthly);
      expect(
          GoogleEventMapper.parseRRule(
              'RRULE:FREQ=YEARLY;UNTIL=20301231', start),
          RecurrenceRule.yearly.withEnd(until: DateTime(2030, 12, 31)));
      expect(GoogleEventMapper.parseRRule('RRULE:FREQ=DAILY;COUNT=10', start),
          RecurrenceRule.daily.withEnd(count: 10));
    });

    test('unsupported rules are rejected rather than guessed', () {
      for (final rule in [
        'RRULE:FREQ=HOURLY',
        'RRULE:FREQ=MONTHLY;BYMONTHDAY=1,15',
        'RRULE:FREQ=MONTHLY;BYDAY=MO,TU',
        'RRULE:FREQ=MONTHLY;BYSETPOS=-1;BYDAY=MO,TU,WE,TH,FR',
        'RRULE:FREQ=YEARLY;BYMONTH=3',
        'RRULE:FREQ=WEEKLY;BYDAY=1MO',
        'RRULE:FREQ=DAILY;INTERVAL=0',
      ]) {
        expect(GoogleEventMapper.parseRRule(rule, start), isNull, reason: rule);
      }
    });
  });

  group('database upgrade', () {
    test('a version 1 database gains sync columns and keeps its events',
        () async {
      sqfliteFfiInit();
      final dir = Directory.systemTemp.createTempSync('calendar_migrate');
      final path = p.join(dir.path, 'calendar.db');
      addTearDown(() async {
        await databaseFactoryFfi.deleteDatabase(path);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      // The schema shipped before sync existed.
      final old = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('''
                CREATE TABLE events (
                  id TEXT PRIMARY KEY, title TEXT NOT NULL,
                  description TEXT NOT NULL DEFAULT '',
                  notes TEXT NOT NULL DEFAULT '',
                  location TEXT NOT NULL DEFAULT '',
                  start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL,
                  all_day INTEGER NOT NULL DEFAULT 0, category_id TEXT,
                  color INTEGER, priority INTEGER NOT NULL DEFAULT 0,
                  reminders TEXT NOT NULL DEFAULT '[]', recurrence TEXT,
                  ex_dates TEXT NOT NULL DEFAULT '[]', series_id TEXT,
                  original_start_ms INTEGER,
                  attachments TEXT NOT NULL DEFAULT '[]',
                  created_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL)''');
              await db.execute(
                  'CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
                  "description TEXT NOT NULL DEFAULT '', due_ms INTEGER, "
                  'has_due_time INTEGER NOT NULL DEFAULT 0, '
                  'priority INTEGER NOT NULL DEFAULT 0, category_id TEXT, '
                  'completed INTEGER NOT NULL DEFAULT 0, completed_ms INTEGER, '
                  'reminder_minutes INTEGER, created_ms INTEGER NOT NULL, '
                  'updated_ms INTEGER NOT NULL)');
              await db.execute(
                  'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, '
                  "color INTEGER NOT NULL, icon TEXT NOT NULL DEFAULT 'label', "
                  'sort_order INTEGER NOT NULL DEFAULT 0)');
              await db.execute(
                  'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
            },
          ));
      final v1Row = makeEvent(title: 'From version 1').toMap()
        ..removeWhere((k, _) => const {
              'remote_id', 'remote_etag', 'synced_ms', 'remote_recurrence',
            }.contains(k));
      await old.insert('events', v1Row);
      await old.close();

      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final repo = SqliteEventRepository(db);
      final event = (await repo.getAll()).single;
      expect(event.title, 'From version 1');
      expect(event.remoteId, isNull);
      expect(event.needsSync, isTrue);

      // The new columns and tables work.
      await repo.upsert(event.copyWith(
          remoteId: () => 'g1', syncedAt: () => event.updatedAt));
      expect((await repo.getAll()).single.needsSync, isFalse);
      final sync = SqliteSyncStateRepository(db);
      await sync.write('account', 'me@example.com');
      await sync.addPendingDeletion('g9');
      expect(await sync.readAll(), {'account': 'me@example.com'});
      expect(await sync.pendingDeletions(), ['g9']);
      await db.close();
    });
  });
}

/// `yyyymmddThhmmssZ` in UTC, as Google writes UNTIL and EXDATE values.
String _stamp(DateTime local) {
  final u = local.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}
