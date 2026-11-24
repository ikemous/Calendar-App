// End-to-end test that runs on a real device or emulator/simulator against
// the real SQLite database:
//
//   flutter test integration_test/app_test.dart -d <device-id>
//
// It creates, finds, edits and deletes an event and a task through the UI,
// and checks that data written through the app is read back from disk.
import 'package:calendar_app/app/app.dart';
import 'package:calendar_app/core/database/app_database.dart';
import 'package:calendar_app/core/notifications/notification_service.dart';
import 'package:calendar_app/core/services/app_services.dart';
import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A separate database file, so the test never touches real user data.
  late String dbPath;

  Future<ProviderContainer> launch(WidgetTester tester) async {
    final db = await AppDatabase.open(path: dbPath);
    final container = ProviderContainer(overrides: [
      bootstrapProvider.overrideWithValue(await AppBootstrap.load(database: db)),
      // Keep the test from showing system permission prompts.
      notificationServiceProvider
          .overrideWithValue(const NoopNotificationService()),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CalendarApp(),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  /// Saving something with a reminder explains why notification permission
  /// is needed. Decline, so no system prompt interrupts the test.
  Future<void> dismissReminderPrompt(WidgetTester tester) async {
    final notNow = find.text('Not now');
    if (notNow.evaluate().isNotEmpty) {
      await tester.tap(notNow);
      await tester.pumpAndSettle();
    }
  }

  setUpAll(() async {
    dbPath = p.join(await getDatabasesPath(), 'integration_test.db');
    await deleteDatabase(dbPath);
  });

  tearDownAll(() => deleteDatabase(dbPath));

  testWidgets('event lifecycle: create, search, edit, delete', (tester) async {
    final container = await launch(tester);

    // Create.
    await tester.tap(find.byTooltip('New event'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Integration event');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await dismissReminderPrompt(tester);
    expect(container.read(eventsProvider).single.title, 'Integration event');

    // Find it through search and open it.
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'integration');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Integration event'));
    await tester.pumpAndSettle();

    // Edit.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Renamed event');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await dismissReminderPrompt(tester);
    expect(container.read(eventsProvider).single.title, 'Renamed event');

    // Delete.
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renamed event'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(container.read(eventsProvider), isEmpty);
  });

  testWidgets('data is still there after the app restarts', (tester) async {
    var container = await launch(tester);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Persistent task');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Persistent task'), findsOneWidget);

    // Throw the whole app away and start again from the database file.
    await tester.pumpWidget(const SizedBox.shrink());
    container = await launch(tester);
    expect(container.read(tasksProvider).single.title, 'Persistent task');

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Persistent task'), findsOneWidget);
  });

  testWidgets('all calendar views open', (tester) async {
    await launch(tester);
    for (final view in ['Week', 'Day', 'Year', 'Month']) {
      // Phones show a menu; wide screens show the views inline.
      final menu = find.byTooltip('Change view');
      if (menu.evaluate().isNotEmpty) {
        await tester.tap(menu);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(view).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    expect(find.text('Load more'), findsOneWidget);
  });
}
