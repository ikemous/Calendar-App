import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/sync/services/device_calendar.dart';
import 'package:calendar_app/features/sync/services/remote_calendar_api.dart';
import 'package:calendar_app/features/sync/services/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sync_fakes.dart';

/// An in-memory phone calendar: rows with the calendar provider's columns.
class FakeDeviceCalendar implements DeviceCalendarPlatform {
  bool permission = true;
  int permissionRequests = 0;
  final Map<int, Map<String, dynamic>> rows = {};
  int _nextId = 100;

  /// Adds a row as another app (or Google's own sync) would.
  int add(Map<String, dynamic> row) {
    final id = _nextId++;
    rows[id] = {'id': id, 'allDay': false, 'reminders': <int>[], ...row};
    return id;
  }

  Map<String, dynamic> byTitle(String title) =>
      rows.values.firstWhere((r) => r['title'] == title);

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<List<DeviceCalendarInfo>> calendars() async => const [
        DeviceCalendarInfo(
            id: '7',
            name: 'Personal',
            account: 'me@gmail.com',
            accountType: 'com.google'),
      ];

  @override
  Future<List<Map<String, dynamic>>> events(String calendarId) async =>
      [for (final r in rows.values) {...r}];
  @override
  Future<Map<String, dynamic>?> event(int id) async =>
      rows[id] == null ? null : {...rows[id]!};

  @override
  Future<int> insert(String calendarId, Map<String, dynamic> values) async =>
      add(values);

  @override
  Future<bool> update(int id, Map<String, dynamic> values) async {
    final row = rows[id];
    if (row == null) return false;
    rows[id] = values['keepTiming'] == true
        ? {...row, ...values}
        : {'id': id, ...values};
    return true;
  }

  @override
  Future<void> delete(int id) async => rows.remove(id);
}

int ms(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  late FakeDeviceCalendar phone;
  late MemoryEventRepository events;
  late MemorySyncStateRepository state;
  var clock = testNow;

  Future<SyncResult> sync() => SyncEngine(
        events: events,
        state: state,
        api: DeviceCalendarApi(phone, '7'),
        timeZone: 'Etc/UTC',
        now: () => clock,
      ).sync();

  /// A local edit, later than the last sync.
  Future<void> editLocally(CalendarEvent e) {
    clock = clock.add(const Duration(minutes: 1));
    return events.upsert(e.copyWith(updatedAt: clock));
  }

  setUp(() {
    phone = FakeDeviceCalendar();
    events = MemoryEventRepository();
    state = MemorySyncStateRepository();
    clock = testNow;
  });

  group('first sync', () {
    test('brings phone events in and sends app events out', () async {
      phone.add({
        'title': 'Dentist',
        'location': 'Clinic',
        'dtstart': ms(DateTime(2026, 11, 25, 14)),
        'dtend': ms(DateTime(2026, 11, 25, 15)),
        'timezone': 'Etc/UTC',
        'reminders': [30],
      });
      await events.upsert(makeEvent(
          title: 'Standup',
          start: DateTime(2026, 11, 24, 9),
          reminders: [10]));

      final result = await sync();
      expect(result.pulled, 1);
      expect(result.pushed, 1);

      final local = await events.getAll();
      final dentist = local.firstWhere((e) => e.title == 'Dentist');
      expect(dentist.start, DateTime(2026, 11, 25, 14));
      expect(dentist.end, DateTime(2026, 11, 25, 15));
      expect(dentist.location, 'Clinic');
      expect(dentist.reminders, [30]);
      expect(dentist.needsSync, isFalse);

      final sent = phone.byTitle('Standup');
      expect(sent['dtstart'], ms(DateTime(2026, 11, 24, 9)));
      expect(sent['dtend'], ms(DateTime(2026, 11, 24, 10)));
      expect(sent['duration'], isNull);
      expect(sent['reminders'], [10]);
      expect(phone.rows, hasLength(2));
    });

    test('a second sync with no changes does nothing', () async {
      phone.add({
        'title': 'Dentist',
        'dtstart': ms(DateTime(2026, 11, 25, 14)),
        'dtend': ms(DateTime(2026, 11, 25, 15)),
      });
      await events.upsert(makeEvent(title: 'Standup'));
      await sync();

      final again = await sync();
      expect(again.pulled, 0);
      expect(again.pushed, 0);
      expect(again.removedLocally + again.removedRemotely, 0);
      expect(phone.rows, hasLength(2));
      expect(await events.getAll(), hasLength(2));
    });
  });

  group('changes on the phone', () {
    late int id;
    setUp(() async {
      id = phone.add({
        'title': 'Dentist',
        'dtstart': ms(DateTime(2026, 11, 25, 14)),
        'dtend': ms(DateTime(2026, 11, 25, 15)),
      });
      await sync();
    });

    test('an edit reaches the app and keeps app-only fields', () async {
      final local = (await events.getAll()).single;
      // Notes live only in the app; set them without marking a change.
      await events.upsert(local.copyWith(notes: 'Bring x-rays'));

      phone.rows[id]!['title'] = 'Dentist (moved)';
      phone.rows[id]!['dtstart'] = ms(DateTime(2026, 11, 26, 9));
      phone.rows[id]!['dtend'] = ms(DateTime(2026, 11, 26, 10));
      final result = await sync();

      expect(result.pulled, 1);
      final updated = (await events.getAll()).single;
      expect(updated.id, local.id);
      expect(updated.title, 'Dentist (moved)');
      expect(updated.start, DateTime(2026, 11, 26, 9));
      expect(updated.notes, 'Bring x-rays');
    });

    test('a deletion removes the event from the app', () async {
      phone.rows.remove(id);
      final result = await sync();
      expect(result.removedLocally, 1);
      expect(await events.getAll(), isEmpty);
    });
  });

  group('changes in the app', () {
    late CalendarEvent local;
    setUp(() async {
      await events.upsert(
          makeEvent(title: 'Standup', start: DateTime(2026, 11, 24, 9)));
      await sync();
      local = (await events.getAll()).single;
    });

    test('an edit updates the same phone event', () async {
      await editLocally(local.copyWith(title: 'Standup (late)', location: 'HQ'));
      final result = await sync();
      expect(result.pushed, 1);
      expect(phone.rows, hasLength(1));
      expect(phone.rows.values.single['title'], 'Standup (late)');
      expect(phone.rows.values.single['location'], 'HQ');
      // And it is not pulled straight back as a "change".
      expect((await sync()).pulled, 0);
    });

    test('a deletion removes the phone event', () async {
      await events.delete(local.id);
      await state.addPendingDeletion(local.remoteId!);
      final result = await sync();
      expect(result.removedRemotely, 1);
      expect(phone.rows, isEmpty);
      expect(await events.getAll(), isEmpty);
    });

    test('when both sides changed, the app\'s edit is kept', () async {
      phone.rows.values.single['title'] = 'Changed on phone';
      await editLocally(local.copyWith(title: 'Changed in app'));
      await sync();
      expect(phone.rows.values.single['title'], 'Changed in app');
      expect((await events.getAll()).single.title, 'Changed in app');
    });

    test('an event deleted on the phone while edited here is re-created',
        () async {
      phone.rows.clear();
      await editLocally(local.copyWith(title: 'Still wanted'));
      // The stale token lists the old id as deleted, but the local edit is
      // newer than the last sync, so the event survives and is re-sent.
      await state.write(SyncKeys.syncToken, null);
      await sync();
      expect(phone.rows.values.single['title'], 'Still wanted');
    });
  });

  group('all-day and repeating events', () {
    test('all-day events keep their dates in both directions', () async {
      phone.add({
        'title': 'Holiday',
        'allDay': true,
        'timezone': 'UTC',
        'dtstart': DateTime.utc(2026, 12, 24).millisecondsSinceEpoch,
        // Exclusive end: two days.
        'dtend': DateTime.utc(2026, 12, 26).millisecondsSinceEpoch,
      });
      await events.upsert(makeEvent(
          title: 'Birthday', start: DateTime(2026, 12, 3), allDay: true));
      await sync();

      final holiday =
          (await events.getAll()).firstWhere((e) => e.title == 'Holiday');
      expect(holiday.allDay, isTrue);
      expect(holiday.start, DateTime(2026, 12, 24));
      expect(holiday.end, DateTime(2026, 12, 25));

      final birthday = phone.byTitle('Birthday');
      expect(birthday['allDay'], isTrue);
      expect(birthday['timezone'], 'UTC');
      expect(birthday['dtstart'],
          DateTime.utc(2026, 12, 3).millisecondsSinceEpoch);
      expect(
          birthday['dtend'], DateTime.utc(2026, 12, 4).millisecondsSinceEpoch);
    });

    test('a repeating phone event arrives with its rule and excluded dates',
        () async {
      phone.add({
        'title': 'Gym',
        'dtstart': DateTime.utc(2026, 11, 2, 18).millisecondsSinceEpoch,
        'duration': 'P3600S',
        'timezone': 'Etc/UTC',
        'rrule': 'FREQ=WEEKLY;BYDAY=MO,WE',
        'exdate': '20261109T180000Z',
      });
      await sync();
      final gym = (await events.getAll()).single;
      expect(gym.recurrence!.frequency, RecurrenceFrequency.weekly);
      expect(gym.recurrence!.weekdays, {DateTime.monday, DateTime.wednesday});
      expect(gym.end.difference(gym.start), const Duration(hours: 1));
      expect(gym.exDates.single,
          DateTime.utc(2026, 11, 9, 18).toLocal());
    });

    test('a repeating app event is stored with a duration, not an end',
        () async {
      await events.upsert(makeEvent(
        title: 'Rent',
        start: DateTime(2026, 1, 1),
        allDay: true,
        recurrence: RecurrenceRule.monthly,
        exDates: [DateTime(2026, 3, 1)],
      ));
      await sync();
      final row = phone.byTitle('Rent');
      expect(row['rrule'], 'FREQ=MONTHLY');
      expect(row['duration'], 'P1D');
      expect(row['dtend'], isNull);
      expect(row['exdate'], '20260301T000000Z');
    });

    test('one changed date of a series becomes its own event', () async {
      final series = phone.add({
        'title': 'Gym',
        'dtstart': DateTime.utc(2026, 11, 2, 18).millisecondsSinceEpoch,
        'duration': 'P3600S',
        'rrule': 'FREQ=DAILY',
      });
      // The phone stores an edited occurrence as a separate row.
      phone.add({
        'title': 'Gym (early)',
        'dtstart': DateTime.utc(2026, 11, 5, 16).millisecondsSinceEpoch,
        'dtend': DateTime.utc(2026, 11, 5, 17).millisecondsSinceEpoch,
        'originalId': series,
        'originalInstanceTime':
            DateTime.utc(2026, 11, 5, 18).millisecondsSinceEpoch,
      });
      await sync();

      final all = await events.getAll();
      final master = all.firstWhere((e) => e.title == 'Gym');
      final moved = all.firstWhere((e) => e.title == 'Gym (early)');
      expect(moved.seriesId, master.id);
      expect(master.exDates, [DateTime.utc(2026, 11, 5, 18).toLocal()]);
      // Nothing is sent back: the phone already has both rows.
      expect((await sync()).pushed, 0);
      expect(phone.rows, hasLength(2));
    });

    test('a rule the app cannot represent is left untouched on the phone',
        () async {
      final id = phone.add({
        'title': 'Payday',
        'dtstart': DateTime.utc(2026, 1, 1, 9).millisecondsSinceEpoch,
        'duration': 'P3600S',
        'rrule': 'FREQ=MONTHLY;BYMONTHDAY=1,15',
      });
      final result = await sync();
      expect(result.unsupportedRepeats, 1);

      final local = (await events.getAll()).single;
      expect(local.recurrence, isNull);
      await editLocally(local.copyWith(title: 'Payday!'));
      await sync();
      expect(phone.rows[id]!['title'], 'Payday!');
      expect(phone.rows[id]!['rrule'], 'FREQ=MONTHLY;BYMONTHDAY=1,15');
      expect(phone.rows[id]!['duration'], 'P3600S');
    });
  });

  group('translation details', () {
    test('durations in the common notations are understood', () {
      Map<String, dynamic> item(String duration, {bool allDay = false}) =>
          DeviceCalendarApi.toItem({
            'id': 1,
            'allDay': allDay,
            'dtstart': DateTime.utc(2026, 1, 1, 9).millisecondsSinceEpoch,
            'duration': duration,
          })!;
      expect(item('P3600S')['end'],
          {'dateTime': DateTime.utc(2026, 1, 1, 10).toIso8601String()});
      expect(item('PT1H30M')['end'],
          {'dateTime': DateTime.utc(2026, 1, 1, 10, 30).toIso8601String()});
      expect(item('P2D', allDay: true)['end'], {'date': '2026-01-03'});
    });

    test('the fingerprint changes only when the event does', () {
      Map<String, dynamic> row(String title) => {
            'id': 1,
            'title': title,
            'dtstart': 1000,
            'dtend': 2000,
            'reminders': [15],
          };
      final a = DeviceCalendarApi.toItem(row('A'))!['etag'];
      expect(DeviceCalendarApi.toItem(row('A'))!['etag'], a);
      expect(DeviceCalendarApi.toItem(row('B'))!['etag'], isNot(a));
    });

    test('rows without a start are skipped, a bad token restarts cleanly',
        () async {
      phone.add({'title': 'Broken'});
      final api = DeviceCalendarApi(phone, '7');
      expect((await api.list()).items, isEmpty);
      expect(() => api.list(syncToken: 'not json'),
          throwsA(isA<SyncTokenExpired>()));
    });
  });

  group('connecting', () {
    test('needs permission and a chosen calendar, and remembers it', () async {
      final auth = DeviceCalendarAuth(phone, state);
      expect(auth.isConfigured, isTrue);
      expect(await auth.accessToken(), isNull);
      expect(await auth.signIn(), isNull);

      final calendars = (await auth.loadCalendars())!;
      expect(phone.permissionRequests, 1);
      auth.choose(calendars.single);
      expect(await auth.signIn(), 'Personal · me@gmail.com');
      expect(await auth.accessToken(), '7');

      // Still connected after a restart...
      expect(await DeviceCalendarAuth(phone, state).accessToken(), '7');
      // ...unless permission is taken away, or the user disconnects.
      phone.permission = false;
      expect(await auth.accessToken(), isNull);
      phone.permission = true;
      await auth.signOut();
      expect(await auth.accessToken(), isNull);
    });

    test('refused permission lists nothing', () async {
      phone.permission = false;
      expect(await DeviceCalendarAuth(phone, state).loadCalendars(), isNull);
    });
  });
}
