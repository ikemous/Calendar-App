import 'dart:convert';

import 'package:calendar_app/core/home_widgets/countdown_widgets.dart';
import 'package:calendar_app/core/services/app_services.dart';
import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

class RecordingWidgetService implements CountdownWidgetService {
  CountdownData? last;
  bool? lockScreen;
  bool? showNext;
  String? imagePath;

  @override
  int? get lockScreenNotificationId => 7001;

  @override
  Future<void> update(
    CountdownData data, {
    required bool lockScreen,
    required bool showNext,
    String? imagePath,
  }) async {
    this.imagePath = imagePath;
    last = data;
    this.lockScreen = lockScreen;
    this.showNext = showNext;
  }
}

void main() {
  // testNow is Monday 23 November 2026, 10:00.
  const featuring = AppSettings(featuredEventId: 'anniversary');

  CalendarEvent anniversary() => makeEvent(
        id: 'anniversary',
        title: 'Anniversary',
        start: DateTime(2020, 3, 3),
        allDay: true,
        recurrence: RecurrenceRule.yearly,
      );

  CountdownData plan(List<CalendarEvent> events,
          [AppSettings settings = featuring]) =>
      CountdownPlanner.plan(events: events, settings: settings, now: testNow);

  group('featured widget', () {
    test('counts down to the next occurrence, then the one after', () {
      final data = plan([anniversary()]);
      expect(data.featured.first.title, 'Anniversary');
      expect(data.featured.first.start, DateTime(2027, 3, 3));
      expect(data.featured.first.until, DateTime(2027, 3, 4));
      expect(data.featured[1].start, DateTime(2028, 3, 3));
      expect(
          CountdownPlanner.daysLabel(data.featured.first, testNow), '100 days');
    });

    test('says Today on the day itself, all day', () {
      final entry = plan([anniversary()]).featured.first;
      final morning = DateTime(2027, 3, 3, 0, 5);
      final night = DateTime(2027, 3, 3, 23, 55);
      expect(CountdownPlanner.daysLabel(entry, morning), 'Today');
      expect(CountdownPlanner.current([entry], night), same(entry));
      expect(CountdownPlanner.current([entry], DateTime(2027, 3, 4)), isNull);
      expect(CountdownPlanner.daysLabel(entry, DateTime(2027, 3, 2, 23)),
          '1 day');
    });

    test('is empty with no featured event, or a one-off event', () {
      expect(plan([anniversary()], const AppSettings()).featured, isEmpty);
      expect(
        plan([makeEvent(id: 'anniversary', start: DateTime(2026, 12, 1))])
            .featured,
        isEmpty,
      );
    });

    test('does not depend on the notification switches', () {
      final data = plan(
        [anniversary(), makeEvent(start: DateTime(2026, 11, 24, 9))],
        const AppSettings(
          featuredEventId: 'anniversary',
          notificationsEnabled: false,
          showNextEventOnLockScreen: false,
        ),
      );
      expect(data.featured, isNotEmpty);
      expect(data.next, hasLength(1));
    });
  });

  group('next event widget', () {
    test('lists upcoming events in order, without the featured one', () {
      final data = plan([
        anniversary(),
        makeEvent(
            id: 'bday',
            title: "Slade's Bday",
            start: DateTime(2026, 12, 3),
            allDay: true),
        makeEvent(id: 'soon', title: 'Dentist', start: DateTime(2026, 11, 25, 14)),
        makeEvent(id: 'past', start: DateTime(2026, 11, 20, 9)),
      ]);
      expect(data.next.map((e) => e.title), ['Dentist', "Slade's Bday"]);
      expect(CountdownPlanner.daysLabel(data.next[0], testNow), '2 days');
      expect(CountdownPlanner.daysLabel(data.next[1], testNow), '10 days');
      // A timed event hands over when it starts; an all-day one at midnight.
      expect(data.next[0].until, DateTime(2026, 11, 25, 14));
      expect(data.next[1].until, DateTime(2026, 12, 4));
    });

    test('an all-day event today is shown as Today', () {
      final data = plan([
        makeEvent(title: 'Birthday', start: DateTime(2026, 11, 23), allDay: true),
        makeEvent(id: 'later', start: DateTime(2026, 11, 23, 9)),
      ]);
      expect(data.next.single.title, 'Birthday');
      expect(CountdownPlanner.daysLabel(data.next.single, testNow), 'Today');
    });

    test('follows a repeating event and looks a year ahead', () {
      final data = plan([
        makeEvent(
            title: 'Rent',
            start: DateTime(2026, 1, 1),
            allDay: true,
            recurrence: RecurrenceRule.monthly),
        makeEvent(id: 'far', title: 'Trip', start: DateTime(2027, 9, 1, 9)),
        makeEvent(id: 'too-far', start: DateTime(2028, 1, 1, 9)),
      ]);
      expect(data.next.first.start, DateTime(2026, 12, 1));
      expect(data.next.map((e) => e.title), contains('Trip'));
      expect(data.next.where((e) => e.start.year == 2028), isEmpty);
    });
  });

  test('encodes to the JSON the native widget reads', () {
    final json = jsonDecode(plan([
      anniversary(),
      makeEvent(id: 'b', title: 'Dentist', start: DateTime(2026, 11, 25, 14)),
    ]).encode()) as Map<String, dynamic>;
    final first = (json['featured'] as List).first as Map<String, dynamic>;
    expect(first['title'], 'Anniversary');
    expect(first['startMs'], DateTime(2027, 3, 3).millisecondsSinceEpoch);
    expect(first['untilMs'], DateTime(2027, 3, 4).millisecondsSinceEpoch);
    expect(((json['next'] as List).single as Map)['title'], 'Dentist');
  });

  test('the native lock screen follows the data and the settings', () async {
    final service = RecordingWidgetService();
    final fake = FakeNotificationService();
    final container = ProviderContainer(overrides: [
      bootstrapProvider
          .overrideWithValue(memoryBootstrap(events: [anniversary()])),
      notificationServiceProvider.overrideWithValue(fake),
      countdownWidgetServiceProvider.overrideWithValue(service),
      clockProvider.overrideWithValue(() => testNow),
    ]);
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);

    await settings.setFeatured('anniversary', true);
    expect(service.last!.featured.first.title, 'Anniversary');
    expect(service.last!.next, isEmpty);
    expect(service.lockScreen, isTrue);
    expect(service.showNext, isTrue);

    await container.read(eventsProvider.notifier).save(makeEvent(
        id: 'b',
        title: 'Dentist',
        start: DateTime(2026, 11, 25, 14),
        reminders: [15]));
    expect(service.last!.next.single.title, 'Dentist');
    // The platform draws the lock screen, so the app posts no cards of its
    // own; reminders are unaffected.
    expect(fake.cards, isEmpty);
    expect(fake.scheduled, hasLength(1));

    expect(service.imagePath, isNull);
    await settings
        .change((s) => s.copyWith(lockScreenImagePath: () => '/pics/us.png'));
    expect(service.imagePath, '/pics/us.png');
    expect(
      AppSettings.fromMap(container.read(settingsProvider).toMap())
          .lockScreenImagePath,
      '/pics/us.png',
    );

    await settings.change((s) => s.copyWith(showNextEventOnLockScreen: false));
    expect(service.showNext, isFalse);
    await settings.change((s) => s.copyWith(notificationsEnabled: false));
    expect(service.lockScreen, isFalse);
  });
}
