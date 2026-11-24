import 'package:calendar_app/app/app.dart';
import 'package:calendar_app/core/notifications/notification_service.dart';
import 'package:calendar_app/core/services/app_services.dart';
import 'package:calendar_app/core/services/file_service.dart';
import 'package:calendar_app/data/models/app_settings.dart';
import 'package:calendar_app/data/models/calendar_event.dart';
import 'package:calendar_app/data/models/category.dart';
import 'package:calendar_app/data/models/recurrence_rule.dart';
import 'package:calendar_app/data/models/task.dart';
import 'package:calendar_app/data/repositories/repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_app/features/sync/providers/sync_controller.dart';
import 'package:material_ui/material_ui.dart';

import 'sync_fakes.dart';

/// Fixed "now" used by tests: Monday 23 November 2026, 10:00.
final DateTime testNow = DateTime(2026, 11, 23, 10);

CalendarEvent makeEvent({
  String id = 'e1',
  String title = 'Meeting',
  DateTime? start,
  DateTime? end,
  bool allDay = false,
  String description = '',
  String notes = '',
  String location = '',
  String? categoryId,
  List<int> reminders = const [],
  RecurrenceRule? recurrence,
  List<DateTime> exDates = const [],
}) {
  final s = start ?? DateTime(2026, 11, 23, 9);
  return CalendarEvent(
    id: id,
    title: title,
    start: s,
    end: end ?? (allDay ? s : s.add(const Duration(hours: 1))),
    allDay: allDay,
    description: description,
    notes: notes,
    location: location,
    categoryId: categoryId,
    reminders: reminders,
    recurrence: recurrence,
    exDates: exDates,
    createdAt: testNow,
    updatedAt: testNow,
  );
}

Task makeTask({
  String id = 't1',
  String title = 'Buy milk',
  DateTime? due,
  bool hasDueTime = false,
  bool completed = false,
  int? reminderMinutes,
  String? categoryId,
  String description = '',
}) =>
    Task(
      id: id,
      title: title,
      description: description,
      dueDate: due,
      hasDueTime: hasDueTime,
      completed: completed,
      reminderMinutes: reminderMinutes,
      categoryId: categoryId,
      createdAt: testNow,
      updatedAt: testNow,
    );

// ---- In-memory repositories (stand in for SQLite in widget tests) --------

class MemoryEventRepository implements EventRepository {
  MemoryEventRepository([Iterable<CalendarEvent> initial = const []])
      : items = {for (final e in initial) e.id: e};
  final Map<String, CalendarEvent> items;

  @override
  Future<List<CalendarEvent>> getAll() async => items.values.toList();
  @override
  Future<void> upsert(CalendarEvent event) async => items[event.id] = event;
  @override
  Future<void> upsertAll(Iterable<CalendarEvent> events) async {
    for (final e in events) {
      items[e.id] = e;
    }
  }

  @override
  Future<void> delete(String id) async => items.remove(id);
  @override
  Future<void> deleteAll() async => items.clear();
}

class MemoryTaskRepository implements TaskRepository {
  MemoryTaskRepository([Iterable<Task> initial = const []])
      : items = {for (final t in initial) t.id: t};
  final Map<String, Task> items;

  @override
  Future<List<Task>> getAll() async => items.values.toList();
  @override
  Future<void> upsert(Task task) async => items[task.id] = task;
  @override
  Future<void> upsertAll(Iterable<Task> tasks) async {
    for (final t in tasks) {
      items[t.id] = t;
    }
  }

  @override
  Future<void> delete(String id) async => items.remove(id);
  @override
  Future<void> deleteAll() async => items.clear();
}

class MemoryCategoryRepository implements CategoryRepository {
  MemoryCategoryRepository([Iterable<Category> initial = Category.defaults])
      : items = {for (final c in initial) c.id: c};
  final Map<String, Category> items;

  @override
  Future<List<Category>> getAll() async => items.values.toList();
  @override
  Future<void> upsert(Category category) async => items[category.id] = category;
  @override
  Future<void> upsertAll(Iterable<Category> categories) async {
    for (final c in categories) {
      items[c.id] = c;
    }
  }

  @override
  Future<void> delete(String id) async => items.remove(id);
  @override
  Future<void> deleteAll() async => items.clear();
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([this.value = const AppSettings()]);
  AppSettings value;

  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

AppBootstrap memoryBootstrap({
  List<CalendarEvent> events = const [],
  List<Task> tasks = const [],
  List<Category> categories = Category.defaults,
  AppSettings settings = const AppSettings(),
  Map<String, String> syncState = const {},
}) =>
    AppBootstrap(
      events: events,
      tasks: tasks,
      categories: categories,
      settings: settings,
      eventRepository: MemoryEventRepository(events),
      taskRepository: MemoryTaskRepository(tasks),
      categoryRepository: MemoryCategoryRepository(categories),
      settingsRepository: MemorySettingsRepository(settings),
      syncStateRepository: MemorySyncStateRepository(syncState),
      syncState: syncState,
    );

// ---- Fakes ---------------------------------------------------------------

/// Records what the app asks the OS to schedule.
class FakeNotificationService implements NotificationService {
  bool permission = true;
  int permissionRequests = 0;
  int cancelAllCalls = 0;
  final List<ScheduledReminder> scheduled = [];

  /// Lock screen cards, shown and pending.
  final List<LockScreenCard> cards = [];
  void Function(String payload)? onTap;

  @override
  Future<void> init({required void Function(String payload) onTap}) async =>
      this.onTap = onTap;
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission = true;
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async =>
      scheduled.add(reminder);
  @override
  Future<void> showCard(LockScreenCard card, {required DateTime now}) async {
    cards
      ..removeWhere((c) => c.id == card.id)
      ..add(card);
  }

  @override
  Future<void> cancelAll({Set<int> keep = const {}}) async {
    cancelAllCalls++;
    scheduled.clear();
    cards.removeWhere((c) => c.showAt != null || !keep.contains(c.id));
  }
}

class FakeFileService implements FileService {
  final Map<String, String> saved = {};
  String? toPick;

  @override
  Future<bool> saveToDevice(
      String fileName, String content, String mimeType) async {
    saved[fileName] = content;
    return true;
  }

  @override
  Future<void> share(String fileName, String content, String mimeType,
          {Rect? origin}) async =>
      saved[fileName] = content;
  @override
  Future<String?> pickTextFile() async => toPick;

  String? imageToPick;
  final List<String> deletedImages = [];

  @override
  Future<String?> pickLockScreenImage() async => imageToPick;
  @override
  Future<void> deleteLockScreenImage(String path) async =>
      deletedImages.add(path);
}

// ---- Harness -------------------------------------------------------------

ProviderContainer makeContainer({
  AppBootstrap? bootstrap,
  FakeNotificationService? notifications,
  DateTime? now,
  FakeCalendarAuth? auth,
  FakeGoogleCalendar? google,
}) {
  final container = ProviderContainer(overrides: [
    calendarAuthProvider
        .overrideWithValue(auth ?? (FakeCalendarAuth()..configured = false)),
    if (google != null)
      remoteCalendarApiFactoryProvider.overrideWithValue((_) => google),
    timeZoneNameProvider.overrideWithValue(() async => 'Etc/UTC'),
    bootstrapProvider.overrideWithValue(bootstrap ?? memoryBootstrap()),
    notificationServiceProvider
        .overrideWithValue(notifications ?? FakeNotificationService()),
    clockProvider.overrideWithValue(() => now ?? testNow),
  ]);
  addTearDown(container.dispose);
  return container;
}

const Size phonePortrait = Size(390, 844);
const Size phoneLandscape = Size(844, 390);
const Size tabletLandscape = Size(1180, 820);
const Size tabletPortrait = Size(820, 1180);

/// Pumps the whole app at [size] with in-memory storage.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  Size size = phonePortrait,
  AppBootstrap? bootstrap,
  FakeNotificationService? notifications,
  FakeFileService? files,
  FakeCalendarAuth? auth,
  FakeGoogleCalendar? google,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    bootstrapProvider.overrideWithValue(bootstrap ?? memoryBootstrap()),
    notificationServiceProvider
        .overrideWithValue(notifications ?? FakeNotificationService()),
    fileServiceProvider.overrideWithValue(files ?? FakeFileService()),
    calendarAuthProvider
        .overrideWithValue(auth ?? (FakeCalendarAuth()..configured = false)),
    if (google != null)
      remoteCalendarApiFactoryProvider.overrideWithValue((_) => google),
    timeZoneNameProvider.overrideWithValue(() async => 'Etc/UTC'),
    clockProvider.overrideWithValue(() => testNow),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const CalendarApp(),
  ));
  await tester.pumpAndSettle();
  return container;
}
