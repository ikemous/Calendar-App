import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/features/calendar/providers/calendar_provider.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/settings/providers/settings_provider.dart';
import 'package:calendar_app/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// A busy week: overlapping, all-day, multi-day and recurring events plus
/// tasks, to stress every layout.
final busyEvents = [
  makeEvent(id: 'a', title: 'Design review', location: 'Room 4'),
  makeEvent(
      id: 'b',
      title: 'Overlapping call with a very long title that must not overflow',
      start: DateTime(2026, 11, 23, 9, 30)),
  makeEvent(id: 'c', title: 'Third at nine', start: DateTime(2026, 11, 23, 9, 15)),
  makeEvent(
      id: 'd',
      title: 'Conference',
      start: DateTime(2026, 11, 24),
      end: DateTime(2026, 11, 26),
      allDay: true),
  makeEvent(
      id: 'e',
      title: 'Gym',
      start: DateTime(2026, 11, 2, 18),
      recurrence: RecurrenceRule.daily),
  makeEvent(
      id: 'f',
      title: 'Overnight',
      start: DateTime(2026, 11, 27, 22),
      end: DateTime(2026, 11, 28, 6)),
  for (var i = 0; i < 6; i++)
    makeEvent(id: 'm$i', title: 'Extra $i', start: DateTime(2026, 11, 25, 8 + i)),
];

final busyTasks = [
  makeTask(id: 't1', title: 'Pay rent', due: DateTime(2026, 11, 23)),
  makeTask(id: 't2', title: 'Old chore', due: DateTime(2026, 11, 20), completed: true),
];

void main() {
  group('responsive layouts', () {
    testWidgets('phones use a bottom navigation bar', (tester) async {
      await pumpApp(tester, size: phonePortrait);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('tablets use a navigation rail', (tester) async {
      await pumpApp(tester, size: tabletPortrait);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('large landscape tablets get a two-pane month view',
        (tester) async {
      await pumpApp(tester,
          size: tabletLandscape,
          bootstrap: memoryBootstrap(events: busyEvents));
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          isTrue);
      // The view switcher is shown inline instead of in a menu.
      expect(find.byType(SegmentedButton<CalendarViewType>), findsOneWidget);
      expect(find.text('Design review'), findsWidgets);
    });

    // Any layout overflow raises an exception and fails these tests.
    for (final (name, size) in [
      ('phone portrait', phonePortrait),
      ('phone landscape', phoneLandscape),
      ('small phone', Size(320, 568)),
      ('tablet portrait', tabletPortrait),
      ('tablet landscape', tabletLandscape),
    ]) {
      testWidgets('every view and tab lays out on $name', (tester) async {
        final container = await pumpApp(
          tester,
          size: size,
          bootstrap: memoryBootstrap(events: busyEvents, tasks: busyTasks),
        );
        final calendar = container.read(calendarProvider.notifier);
        for (final view in [
          CalendarViewType.month,
          CalendarViewType.week,
          CalendarViewType.day,
          CalendarViewType.year,
        ]) {
          calendar.setView(view);
          await tester.pumpAndSettle();
          calendar.page(1);
          await tester.pumpAndSettle();
          calendar.goToToday();
          await tester.pumpAndSettle();
        }
        for (final tab in ['Agenda', 'Tasks', 'Search', 'Settings']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
        }
        expect(find.text('Appearance'), findsOneWidget);
      });
    }

    testWidgets('dark theme and compact month dots render', (tester) async {
      await pumpApp(
        tester,
        bootstrap: memoryBootstrap(
          events: busyEvents,
          settings: const AppSettings(
            themeMode: ThemeMode.dark,
            showEventTitlesInMonth: false,
            use24Hour: true,
            firstDayOfWeek: DateTime.sunday,
          ),
        ),
      );
      final context = tester.element(find.byType(NavigationBar));
      expect(Theme.of(context).brightness, Brightness.dark);
    });
  });

  group('calendar navigation', () {
    testWidgets('next, previous and today change the visible month',
        (tester) async {
      await pumpApp(tester);
      expect(find.text('November 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Today'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
    });

    testWidgets('the view menu switches between views', (tester) async {
      final container = await pumpApp(tester);
      for (final view in ['Week', 'Day', 'Year', 'Month']) {
        await tester.tap(find.byTooltip('Change view'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(view).last);
        await tester.pumpAndSettle();
        expect(container.read(calendarProvider).view.label, view);
      }
    });

    testWidgets('the title opens a month and year picker', (tester) async {
      final container = await pumpApp(tester);
      await tester.tap(find.text('November 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mar'));
      await tester.pumpAndSettle();
      expect(container.read(calendarProvider).selected, DateTime(2027, 3));
      expect(find.text('March 2027'), findsOneWidget);
    });

    testWidgets('selecting a day shows its events', (tester) async {
      await pumpApp(tester,
          bootstrap: memoryBootstrap(events: [
            makeEvent(title: 'Today thing'),
            makeEvent(
                id: 'x', title: 'Friday thing', start: DateTime(2026, 11, 27, 12)),
          ]));
      expect(find.text('Monday, November 23, 2026'), findsOneWidget);
      expect(find.text('Nothing planned'), findsNothing);

      await tester.tap(find.bySemanticsLabel(RegExp('^Friday, November 27')));
      await tester.pumpAndSettle();
      expect(find.text('Friday, November 27, 2026'), findsOneWidget);
      // Once in the grid cell and once in the day list.
      expect(find.text('Friday thing'), findsNWidgets(2));
    });
  });

  group('events', () {
    testWidgets('create an event from the calendar', (tester) async {
      final fake = FakeNotificationService();
      final container = await pumpApp(tester, notifications: fake);

      await tester.tap(find.byTooltip('New event'));
      await tester.pumpAndSettle();
      expect(find.text('New event'), findsOneWidget);

      // Saving without a title is refused.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Give the event a title'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Coffee with Ana');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = container.read(eventsProvider).single;
      expect(saved.title, 'Coffee with Ana');
      // Today is selected, so the event starts at the next full hour.
      expect(saved.start, DateTime(2026, 11, 23, 11));
      expect(saved.end, DateTime(2026, 11, 23, 12));
      // The default reminder is applied and scheduled.
      expect(saved.reminders, [15]);
      expect(fake.scheduled.single.when, DateTime(2026, 11, 23, 10, 45));
      expect(find.text('Coffee with Ana'), findsWidgets);
    });

    testWidgets('asks for notification permission, with a reason, when needed',
        (tester) async {
      final fake = FakeNotificationService()..permission = false;
      await pumpApp(tester, notifications: fake);

      await tester.tap(find.byTooltip('New event'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Call');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Allow reminders?'), findsOneWidget);
      expect(fake.permissionRequests, 0);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(fake.permissionRequests, 1);
    });

    testWidgets('open, edit and delete an event', (tester) async {
      final container = await pumpApp(tester,
          bootstrap: memoryBootstrap(
              events: [makeEvent(title: 'Dentist', location: 'Clinic')]));

      await tester.tap(find.text('Dentist').last);
      await tester.pumpAndSettle();
      expect(find.text('Clinic'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Dentist (moved)');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(container.read(eventsProvider).single.title, 'Dentist (moved)');

      await tester.tap(find.text('Dentist (moved)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete event?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(container.read(eventsProvider), isEmpty);
      expect(find.text('Nothing planned'), findsOneWidget);
    });

    testWidgets('feature a repeating event on the lock screen', (tester) async {
      final fake = FakeNotificationService();
      final container = await pumpApp(tester,
          notifications: fake,
          bootstrap: memoryBootstrap(events: [
            makeEvent(
              title: 'Dentist',
              start: DateTime(2026, 11, 23, 15),
              recurrence: RecurrenceRule.weekly,
            ),
          ]));

      await tester.tap(find.text('Dentist').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Feature on lock screen'));
      await tester.pumpAndSettle();

      expect(find.text('Featured on the lock screen'), findsWidgets);
      expect(container.read(settingsProvider).featuredEventId, 'e1');
      final shown = fake.cards.where((c) => c.showAt == null).single;
      expect(shown.label, 'Featured');
      expect(shown.title, 'Dentist');

      await tester.tap(find.byTooltip('Remove from lock screen'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).featuredEventId, isNull);
      expect(fake.cards.every((c) => c.label == 'Next'), isTrue);
    });

    testWidgets('one-off events cannot be featured', (tester) async {
      await pumpApp(tester,
          bootstrap: memoryBootstrap(events: [
            makeEvent(title: 'Dentist', start: DateTime(2026, 11, 23, 15)),
          ]));
      await tester.tap(find.text('Dentist').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Feature on lock screen'), findsNothing);
    });

    testWidgets('deleting a recurring event offers the three scopes',
        (tester) async {
      final container = await pumpApp(tester,
          bootstrap: memoryBootstrap(events: [
            makeEvent(title: 'Standup', recurrence: RecurrenceRule.daily),
          ]));

      await tester.tap(find.text('Standup').last);
      await tester.pumpAndSettle();
      expect(find.text('Daily'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This event only'), findsOneWidget);
      expect(find.text('This and future events'), findsOneWidget);
      expect(find.text('Entire series'), findsOneWidget);

      await tester.tap(find.text('This event only'));
      await tester.pumpAndSettle();
      final series = container.read(eventsProvider).single;
      expect(series.exDates, [DateTime(2026, 11, 23, 9)]);
      expect(find.text('Nothing planned'), findsOneWidget);
    });
  });

  group('tasks', () {
    testWidgets('add a task and mark it done', (tester) async {
      final container = await pumpApp(tester);
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.text('All caught up'), findsOneWidget);

      await tester.tap(find.byTooltip('New task'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Water plants');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Water plants'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(container.read(tasksProvider).single.completed, isTrue);
      // Completed tasks leave the "To do" list...
      expect(find.text('Water plants'), findsNothing);

      // ...and are shown struck through under "Done".
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(find.text('Water plants'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('dated tasks appear in the calendar', (tester) async {
      await pumpApp(tester,
          bootstrap: memoryBootstrap(
              tasks: [makeTask(title: 'Pay rent', due: DateTime(2026, 11, 23))]));
      // In the month grid and in the selected day's list.
      expect(find.text('Pay rent'), findsNWidgets(2));
    });
  });

  group('search', () {
    testWidgets('find an event and jump to it', (tester) async {
      await pumpApp(tester,
          bootstrap: memoryBootstrap(events: [
            makeEvent(title: 'Quarterly review', location: 'Boardroom'),
            makeEvent(id: 'z', title: 'Lunch'),
          ]));
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'boardroom');
      await tester.pumpAndSettle();
      expect(find.text('Quarterly review'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
      expect(find.textContaining('Mon, Nov 23'), findsOneWidget);

      await tester.tap(find.text('Quarterly review'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.text('Boardroom'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('switching to 24-hour time is saved', (tester) async {
      final bootstrap = memoryBootstrap();
      final container = await pumpApp(tester, bootstrap: bootstrap);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('24-hour time'), 200);
      await tester.tap(find.text('24-hour time'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).use24Hour, isTrue);
      expect((await bootstrap.settingsRepository.load()).use24Hour, isTrue);
    });

    testWidgets('creating a backup writes a JSON file', (tester) async {
      final files = FakeFileService();
      await pumpApp(tester,
          files: files,
          bootstrap: memoryBootstrap(events: [makeEvent(title: 'Keep me')]));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('Backup, restore and export'), 200);
      await tester.tap(find.text('Backup, restore and export'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to device'));
      await tester.pumpAndSettle();

      expect(files.saved.keys.single, 'calendar-backup-20261123.json');
      expect(files.saved.values.single, contains('Keep me'));
    });
  });
}
