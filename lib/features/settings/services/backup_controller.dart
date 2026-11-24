import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/services/app_services.dart';
import '../../../core/services/export_service.dart';
import '../../../data/models/category.dart';
import '../../categories/providers/categories_provider.dart';
import '../../events/providers/events_provider.dart';
import '../../sync/providers/sync_controller.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../providers/settings_provider.dart';

enum ImportMode {
  /// Keep existing data; add items from the backup and update matching ones.
  merge,

  /// Remove existing data and use only what is in the backup.
  replace,
}

class ImportSummary {
  const ImportSummary(this.events, this.tasks, this.categories);
  final int events;
  final int tasks;
  final int categories;
}

/// Builds exports from the current data and restores backups.
class BackupController {
  BackupController(this._ref);
  final Ref _ref;

  BackupData snapshot() => BackupData(
        events: _ref.read(eventsProvider),
        tasks: _ref.read(tasksProvider),
        categories: _ref.read(categoriesProvider),
        settings: _ref.read(settingsProvider),
      );

  String exportJson() =>
      ExportService.toJson(snapshot(), exportedAt: _ref.read(clockProvider)());

  String exportCsv() => ExportService.eventsToCsv(
      _ref.read(eventsProvider), _ref.read(categoryMapProvider));

  String exportIcs() => ExportService.toIcs(
        _ref.read(eventsProvider),
        _ref.read(categoryMapProvider),
        tasks: _ref.read(tasksProvider),
        now: _ref.read(clockProvider)(),
      );

  /// Restores a JSON backup. The file is parsed and validated in full
  /// before any stored data is touched, so a bad file can never wipe the
  /// calendar. Throws [BackupFormatException] for unreadable files.
  Future<ImportSummary> importJson(String source, ImportMode mode) async {
    final data = ExportService.fromJson(source);
    final events = _ref.read(eventRepositoryProvider);
    final tasks = _ref.read(taskRepositoryProvider);
    final categories = _ref.read(categoryRepositoryProvider);

    if (mode == ImportMode.replace) {
      await events.deleteAll();
      await tasks.deleteAll();
      await categories.deleteAll();
    }
    await categories.upsertAll(data.categories);
    await events.upsertAll(data.events);
    await tasks.upsertAll(data.tasks);
    if (mode == ImportMode.replace) {
      await _ref.read(syncControllerProvider.notifier).resetAfterDataReset();
    }
    if (mode == ImportMode.replace && data.settings != null) {
      await _ref.read(settingsRepositoryProvider).save(data.settings!);
    }
    await _reloadAll();
    return ImportSummary(
        data.events.length, data.tasks.length, data.categories.length);
  }

  /// Permanently removes all events and tasks from this device and
  /// restores the default categories. Settings are kept. Nothing is deleted
  /// from a connected Google Calendar.
  Future<void> eraseAll() async {
    await _ref.read(eventRepositoryProvider).deleteAll();
    await _ref.read(taskRepositoryProvider).deleteAll();
    final categories = _ref.read(categoryRepositoryProvider);
    await categories.deleteAll();
    await categories.upsertAll(Category.defaults);
    await _ref.read(syncControllerProvider.notifier).resetAfterDataReset();
    await _reloadAll();
  }

  Future<void> _reloadAll() async {
    await _ref.read(categoriesProvider.notifier).reload();
    await _ref.read(eventsProvider.notifier).reload();
    await _ref.read(tasksProvider.notifier).reload();
    await _ref.read(settingsProvider.notifier).reload();
    await _ref.read(reminderSchedulerProvider).sync();
  }
}

final backupControllerProvider =
    Provider<BackupController>((ref) => BackupController(ref));
