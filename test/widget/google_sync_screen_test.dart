import 'package:calendar_app/features/events/providers/events_provider.dart';
import 'package:calendar_app/features/sync/providers/sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sync_fakes.dart';

Future<void> openGoogleScreen(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Google Calendar'), 200);
  // Bring the whole row into view, not just its first pixels.
  await tester.ensureVisible(find.text('Google Calendar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Google Calendar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains that sync is unavailable until client ids are added',
      (tester) async {
    await pumpApp(tester);
    await openGoogleScreen(tester);

    expect(find.textContaining('not set up in this build'), findsOneWidget);
    expect(find.text('Connect Google account'), findsNothing);
  });

  testWidgets('connect asks first, then syncs both ways', (tester) async {
    final google = FakeGoogleCalendar()
      ..remoteAdd({
        'summary': 'From Google',
        'start': {'dateTime': DateTime(2026, 11, 23, 15).toUtc().toIso8601String()},
        'end': {'dateTime': DateTime(2026, 11, 23, 16).toUtc().toIso8601String()},
      });
    final container = await pumpApp(
      tester,
      google: google,
      auth: FakeCalendarAuth(),
      bootstrap: memoryBootstrap(events: [makeEvent(title: 'From the app')]),
    );
    await openGoogleScreen(tester);

    await tester.tap(find.text('Connect Google account'));
    await tester.pumpAndSettle();
    // The user is told what will happen before anything is uploaded.
    expect(find.textContaining('the 1 events already in this app'),
        findsOneWidget);
    expect(google.inserts, 0);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('1 received, 1 sent, 0 removed'), findsOneWidget);
    expect(google.bySummary('From the app'), isNotNull);
    expect(container.read(eventsProvider).map((e) => e.title),
        unorderedEquals(['From the app', 'From Google']));

    // Disconnect keeps everything.
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect').last);
    await tester.pumpAndSettle();
    expect(container.read(syncControllerProvider).connected, isFalse);
    expect(container.read(eventsProvider), hasLength(2));
    expect(google.live, hasLength(2));
  });
}
