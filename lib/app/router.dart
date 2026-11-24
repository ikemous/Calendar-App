import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models/app_settings.dart';
import '../features/calendar/screens/agenda_screen.dart';
import '../features/calendar/screens/calendar_screen.dart';
import '../features/categories/screens/categories_screen.dart';
import '../features/events/screens/event_detail_screen.dart';
import '../features/events/screens/event_edit_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/settings/providers/settings_provider.dart';
import '../features/settings/screens/about_screen.dart';
import '../features/settings/screens/backup_screen.dart';
import '../features/settings/screens/privacy_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/sync/screens/google_sync_screen.dart';
import '../features/tasks/screens/task_edit_screen.dart';
import '../features/tasks/screens/tasks_screen.dart';
import 'app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

DateTime? _millis(String? value) {
  final ms = int.tryParse(value ?? '');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// App routes.
///
/// * `/calendar`, `/agenda`, `/tasks`, `/search`, `/settings` are the tabs.
/// * `/event/new?start=<ms>` creates an event.
/// * `/event/:id?occ=<ms>` shows one occurrence; `/event/:id/edit` edits it.
/// * `/task/new?due=<ms>` and `/task/:id` create and edit tasks.
final routerProvider = Provider<GoRouter>((ref) {
  final startOnAgenda =
      ref.read(settingsProvider).defaultView == CalendarViewType.agenda;
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: startOnAgenda ? '/agenda' : '/calendar',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/calendar',
              builder: (context, state) => const CalendarScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/agenda',
              builder: (context, state) => const AgendaScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/tasks',
              builder: (context, state) => const TasksScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'categories',
                  builder: (context, state) => const CategoriesScreen(),
                ),
                GoRoute(
                  path: 'google',
                  builder: (context, state) => const GoogleSyncScreen(),
                ),
                GoRoute(
                  path: 'backup',
                  builder: (context, state) => const BackupScreen(),
                ),
                GoRoute(
                  path: 'privacy',
                  builder: (context, state) => const PrivacyScreen(),
                ),
                GoRoute(
                  path: 'about',
                  builder: (context, state) => const AboutScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
      GoRoute(
        path: '/event/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => EventEditScreen(
          initialStart: _millis(state.uri.queryParameters['start']),
          initialAllDay: state.uri.queryParameters['allDay'] == '1',
        ),
      ),
      GoRoute(
        path: '/event/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => EventDetailScreen(
          eventId: state.pathParameters['id']!,
          occurrenceStart: _millis(state.uri.queryParameters['occ']),
        ),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => EventEditScreen(
              eventId: state.pathParameters['id'],
              occurrenceStart: _millis(state.uri.queryParameters['occ']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/task/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => TaskEditScreen(
          initialDue: _millis(state.uri.queryParameters['due']),
        ),
      ),
      GoRoute(
        path: '/task/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            TaskEditScreen(taskId: state.pathParameters['id']),
      ),
    ],
  );
});
