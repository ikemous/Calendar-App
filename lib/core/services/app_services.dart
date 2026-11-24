import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/datasources/sqlite_repositories.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/repositories.dart';
import '../database/app_database.dart';
import '../home_widgets/countdown_widgets.dart';
import '../notifications/notification_service.dart';

/// Everything loaded from disk before the first frame. Loading it up front
/// lets the rest of the app read state synchronously.
class AppBootstrap {
  const AppBootstrap({
    required this.events,
    required this.tasks,
    required this.categories,
    required this.settings,
    required this.eventRepository,
    required this.taskRepository,
    required this.categoryRepository,
    required this.settingsRepository,
    required this.syncStateRepository,
    this.syncState = const {},
  });

  final List<CalendarEvent> events;
  final List<Task> tasks;
  final List<Category> categories;
  final AppSettings settings;
  final EventRepository eventRepository;
  final TaskRepository taskRepository;
  final CategoryRepository categoryRepository;
  final SettingsRepository settingsRepository;
  final SyncStateRepository syncStateRepository;

  /// Persisted cloud-sync state (see `SyncStateRepository`).
  final Map<String, String> syncState;

  /// Opens the database and reads all persisted data.
  static Future<AppBootstrap> load({Database? database}) async {
    final db = database ?? await AppDatabase.open();
    final events = SqliteEventRepository(db);
    final tasks = SqliteTaskRepository(db);
    final categories = SqliteCategoryRepository(db);
    final settings = SqliteSettingsRepository(db);
    final syncState = SqliteSyncStateRepository(db);
    return AppBootstrap(
      events: await events.getAll(),
      tasks: await tasks.getAll(),
      categories: await categories.getAll(),
      settings: await settings.load(),
      eventRepository: events,
      taskRepository: tasks,
      categoryRepository: categories,
      settingsRepository: settings,
      syncStateRepository: syncState,
      syncState: await syncState.readAll(),
    );
  }
}

/// Overridden in `main()` (and in tests) with the loaded data.
final bootstrapProvider = Provider<AppBootstrap>(
  (ref) => throw UnimplementedError('bootstrapProvider must be overridden'),
);

final eventRepositoryProvider =
    Provider<EventRepository>((ref) => ref.watch(bootstrapProvider).eventRepository);
final taskRepositoryProvider =
    Provider<TaskRepository>((ref) => ref.watch(bootstrapProvider).taskRepository);
final categoryRepositoryProvider = Provider<CategoryRepository>(
    (ref) => ref.watch(bootstrapProvider).categoryRepository);
final syncStateRepositoryProvider = Provider<SyncStateRepository>(
    (ref) => ref.watch(bootstrapProvider).syncStateRepository);
final settingsRepositoryProvider = Provider<SettingsRepository>(
    (ref) => ref.watch(bootstrapProvider).settingsRepository);

/// Overridden in `main()` with the platform implementation.
final notificationServiceProvider =
    Provider<NotificationService>((ref) => const NoopNotificationService());

/// Overridden in `main()` with the platform implementation.
final countdownWidgetServiceProvider = Provider<CountdownWidgetService>(
    (ref) => const NoopCountdownWidgetService());

/// Injectable clock so date-dependent logic can be tested.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
