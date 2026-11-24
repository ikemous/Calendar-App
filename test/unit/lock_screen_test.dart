import 'package:calendar_app/core/notifications/lock_screen_planner.dart';
import 'package:calendar_app/core/notifications/notification_service.dart';
import 'package:calendar_app/core/notifications/reminder_planner.dart';
import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/events/services/series_editor.dart';
import 'package:calendar_app/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  // testNow is Monday 23 November 2026, 10:00.
  const settings = AppSettings(use24Hour: true);

  List<LockScreenCard> plan(List<CalendarEvent> events,
          [AppSettings s = settings]) =>
      LockScreenPlanner.plan(events: events, settings: s, now: testNow);

  group('next event', () {
    test('shows the next event now and hands over at each start', () {
      final cards = plan([
        makeEvent(id: 'c', title: 'Breakfast', start: DateTime(2026, 11, 24, 9)),
        makeEvent(
            id: 'a', title: 'Standup', start: DateTime(2026, 11, 23, 11), location: 'HQ'),
        makeEvent(id: 'b', title: 'Review', start: DateTime(2026, 11, 23, 14)),
      ]);
      expect(cards.map((c) => c.title), ['Standup', 'Review', 'Breakfast']);
      expect(cards.map((c) => c.showAt), [
        null,
        DateTime(2026, 11, 23, 11),
        DateTime(2026, 11, 23, 14),
      ]);
      expect(cards.map((c) => c.hideAt), [
        DateTime(2026, 11, 23, 11),
        DateTime(2026, 11, 23, 14),
        DateTime(2026, 11, 24, 9),
      ]);
      expect(cards.first.label, LockScreenPlanner.nextLabel);
      expect(cards.first.body, 'Mon, Nov 23 · 11:00 · HQ');
      expect(NotificationTarget.decode(cards.first.payload)!.id, 'a');
    });

    test('ignores events that have started or are beyond the horizon', () {
      final cards = plan([
        makeEvent(id: 'past', start: DateTime(2026, 11, 22, 9)),
        makeEvent(
            id: 'running',
            start: DateTime(2026, 11, 23, 9, 30),
            end: DateTime(2026, 11, 23, 10, 30)),
        makeEvent(id: 'today', start: DateTime(2026, 11, 23), allDay: true),
        makeEvent(id: 'far', start: DateTime(2027, 3, 1, 9)),
      ]);
      expect(cards, isEmpty);
    });

    test('events starting together share one card', () {
      final at = DateTime(2026, 11, 23, 12);
      final cards = plan([
        makeEvent(id: 'a', title: 'Lunch', start: at),
        makeEvent(id: 'b', title: 'Webinar', start: at),
        makeEvent(id: 'c', title: 'Later', start: DateTime(2026, 11, 23, 16)),
      ]);
      expect(cards, hasLength(2));
      expect(cards.first.title, 'Lunch');
      expect(cards.first.body, endsWith('+1 more'));
      expect(cards.last.showAt, at);
    });

    test('follows a recurring event, within the cap', () {
      final cards = plan([
        makeEvent(start: DateTime(2026, 1, 1, 8), recurrence: RecurrenceRule.daily),
      ]);
      expect(cards, hasLength(LockScreenPlanner.maxNext));
      expect(cards.first.hideAt, DateTime(2026, 11, 24, 8));
      expect(cards.map((c) => c.id).toSet(), hasLength(cards.length));
      expect(cards.where((c) => c.showAt == null), hasLength(1));
    });

    test('is off when switched off, or when notifications are off', () {
      final e = makeEvent(start: DateTime(2026, 11, 23, 15));
      expect(plan([e], const AppSettings(showNextEventOnLockScreen: false)),
          isEmpty);
      expect(
        plan(
            [e],
            const AppSettings(
                notificationsEnabled: false, featuredEventId: 'e1')),
        isEmpty,
      );
    });

    test('never includes the description or notes', () {
      final c = plan([
        makeEvent(
          start: DateTime(2026, 11, 23, 15),
          description: 'SECRET-DESCRIPTION',
          notes: 'SECRET-NOTES',
        ),
      ]).single;
      expect('${c.label} ${c.title} ${c.body}', isNot(contains('SECRET')));
    });
  });

  group('featured event', () {
    const featuring = AppSettings(
      use24Hour: true,
      showNextEventOnLockScreen: false,
      featuredEventId: 'e1',
    );
    // Every day, 8:00 to 9:00.
    CalendarEvent daily({DateTime? start, DateTime? end}) => makeEvent(
          title: 'Gym',
          start: start ?? DateTime(2026, 1, 1, 8),
          end: end,
          recurrence: RecurrenceRule.daily,
        );

    test('shows the next occurrence, then hands over to the ones after', () {
      final cards = plan([
        daily(),
        makeEvent(id: 'other', start: DateTime(2026, 11, 24, 12)),
      ], featuring);
      expect(cards, hasLength(LockScreenPlanner.maxFeatured));
      expect(cards.every((c) => c.title == 'Gym'), isTrue);
      expect(cards.every((c) => c.label == LockScreenPlanner.featuredLabel),
          isTrue);
      expect(cards.first.showAt, isNull);
      expect(cards.first.hideAt, DateTime(2026, 11, 24, 9));
      expect(cards.first.body, 'Tue, Nov 24 · 08:00');
      expect(cards[1].showAt, DateTime(2026, 11, 24, 9));
      expect(cards[1].hideAt, DateTime(2026, 11, 25, 9));
      expect(cards[1].body, 'Wed, Nov 25 · 08:00');
      expect(cards.map((c) => c.id).toSet(), hasLength(cards.length));
    });

    test('an occurrence in progress stays until it ends', () {
      final cards = plan([
        daily(
            start: DateTime(2026, 1, 1, 9, 30), end: DateTime(2026, 1, 1, 10, 30)),
      ], featuring);
      expect(cards.first.hideAt, DateTime(2026, 11, 23, 10, 30));
      expect(cards[1].showAt, DateTime(2026, 11, 23, 10, 30));
    });

    test('only a repeating event can be featured', () {
      expect(plan([makeEvent(start: DateTime(2026, 11, 28, 15))], featuring),
          isEmpty);
    });

    test('a series that has ended shows nothing', () {
      final ended = makeEvent(
        start: DateTime(2026, 1, 1, 8),
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          until: DateTime(2026, 11, 22),
        ),
      );
      expect(plan([ended], featuring), isEmpty);
      expect(LockScreenPlanner.currentOccurrence(ended, testNow), isNull);
    });

    test('has its own slot beside the next event', () {
      final cards = plan([
        daily(),
        makeEvent(id: 'b', title: 'Dinner', start: DateTime(2026, 11, 23, 19)),
      ], const AppSettings(featuredEventId: 'e1'));
      final now = cards.where((c) => c.showAt == null);
      expect(now.map((c) => '${c.label}: ${c.title}'),
          ['Featured: Gym', 'Next: Dinner']);
      // The featured event never appears in the next-event slot.
      expect(
        cards.where((c) =>
            c.label == LockScreenPlanner.nextLabel && c.title == 'Gym'),
        isEmpty,
      );
    });
  });

  test('pending notifications stay within the iOS limit of 64', () {
    // The first card of each slot is shown immediately; the rest are
    // pending.
    expect(
      ReminderPlanner.maxScheduled +
          LockScreenPlanner.maxNext -
          1 +
          LockScreenPlanner.maxFeatured -
          1,
      lessThanOrEqualTo(64),
    );
  });

  test('lock screen settings survive a save and load', () {
    const s = AppSettings(
        showNextEventOnLockScreen: false, featuredEventId: 'a');
    final loaded = AppSettings.fromMap(s.toMap());
    expect(loaded.showNextEventOnLockScreen, isFalse);
    expect(loaded.featuredEventId, 'a');
    expect(AppSettings.fromMap(const {}).showNextEventOnLockScreen, isTrue);
    expect(AppSettings.fromMap(const {}).featuredEventId, isNull);
  });

  group('the lock screen follows the data', () {
    test('saving and deleting an event updates the next-event card', () async {
      final fake = FakeNotificationService();
      final c = makeContainer(notifications: fake);
      final events = c.read(eventsProvider.notifier);
      final e = makeEvent(title: 'Standup', start: DateTime(2026, 11, 23, 11));
      await events.save(e);
      expect(fake.cards.single.title, 'Standup');

      await events.save(makeEvent(
          id: 'sooner', title: 'Coffee', start: DateTime(2026, 11, 23, 10, 30)));
      expect(fake.cards.map((c) => c.title),
          unorderedEquals(['Coffee', 'Standup']));
      expect(fake.cards.firstWhere((c) => c.title == 'Standup').showAt,
          DateTime(2026, 11, 23, 10, 30));

      await events.deleteOccurrence(
          master: e, occurrenceStart: e.start, scope: RecurrenceScope.all);
      expect(fake.cards.single.title, 'Coffee');
    });

    test('featuring and unfeaturing an event adds and removes its card',
        () async {
      final fake = FakeNotificationService();
      final e = makeEvent(
          title: 'Gym',
          start: DateTime(2026, 1, 1, 8),
          recurrence: RecurrenceRule.weekly);
      final other = makeEvent(
          id: 'yoga',
          title: 'Yoga',
          start: DateTime(2026, 1, 1, 18),
          recurrence: RecurrenceRule.weekly);
      final c = makeContainer(
        bootstrap: memoryBootstrap(
          events: [e, other],
          settings: const AppSettings(showNextEventOnLockScreen: false),
        ),
        notifications: fake,
      );
      final settings = c.read(settingsProvider.notifier);

      await settings.setFeatured(e.id, true);
      expect(fake.cards, isNotEmpty);
      expect(fake.cards.every((c) => c.title == 'Gym'), isTrue);
      expect(c.read(settingsProvider).featuredEventId, e.id);

      // Featuring another event replaces the first: there is one slot.
      await settings.setFeatured(other.id, true);
      expect(fake.cards.every((c) => c.title == 'Yoga'), isTrue);
      expect(fake.cards.where((c) => c.showAt == null), hasLength(1));

      // Unfeaturing an event that is not featured changes nothing.
      await settings.setFeatured(e.id, false);
      expect(c.read(settingsProvider).featuredEventId, other.id);

      await settings.setFeatured(other.id, false);
      expect(fake.cards, isEmpty);
    });

    test('switching the next-event card off removes it', () async {
      final fake = FakeNotificationService();
      final c = makeContainer(notifications: fake);
      await c
          .read(eventsProvider.notifier)
          .save(makeEvent(start: DateTime(2026, 11, 23, 11)));
      expect(fake.cards, hasLength(1));

      await c
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(showNextEventOnLockScreen: false));
      expect(fake.cards, isEmpty);
    });
  });
}
