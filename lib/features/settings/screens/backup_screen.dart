import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/export_service.dart';
import '../../../core/services/file_service.dart';
import '../../../shared/widgets/common.dart';
import '../../events/providers/events_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../services/backup_controller.dart';

enum _Target { save, share }

/// Backup, restore and export of calendar data.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  String _stamp() {
    final n = ref.read(clockProvider)();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}';
  }

  /// Asks where the file should go, then writes it there.
  Future<void> _export({
    required String name,
    required String mimeType,
    required String Function() build,
  }) async {
    final target = await showModalBottomSheet<_Target>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to device'),
              onTap: () => Navigator.of(context).pop(_Target.save),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share…'),
              subtitle: const Text('Send the file to another app'),
              onTap: () => Navigator.of(context).pop(_Target.share),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    // Anchor for the share sheet on iPad.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & Size(box.size.width, 120);

    setState(() => _busy = true);
    try {
      final files = ref.read(fileServiceProvider);
      final content = build();
      if (target == _Target.save) {
        final saved = await files.saveToDevice(name, content, mimeType);
        if (mounted && saved) showSnack(context, 'Saved $name');
      } else {
        await files.share(name, content, mimeType, origin: origin);
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final controller = ref.read(backupControllerProvider);
    setState(() => _busy = true);
    try {
      final source = await ref.read(fileServiceProvider).pickTextFile();
      if (source == null || !mounted) return;

      // Validate before asking, so a bad file never gets as far as "replace".
      final data = ExportService.fromJson(source);
      final mode = await showDialog<ImportMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore backup'),
          content: Text(
            'This backup contains ${data.events.length} events, '
            '${data.tasks.length} tasks and ${data.categories.length} '
            'categories.\n\n'
            'Merge adds them to what you have now. Replace deletes '
            'everything currently in the app first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ImportMode.replace),
              child: Text('Replace',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ImportMode.merge),
              child: const Text('Merge'),
            ),
          ],
        ),
      );
      if (mode == null || !mounted) return;
      if (mode == ImportMode.replace) {
        final ok = await confirmDialog(
          context,
          title: 'Replace everything?',
          message: 'All events, tasks and categories currently in the app '
              'will be deleted and replaced with the backup. This cannot be '
              'undone.',
          confirmLabel: 'Replace',
        );
        if (!ok || !mounted) return;
      }
      final summary = await controller.importJson(source, mode);
      if (mounted) {
        showSnack(context,
            'Restored ${summary.events} events and ${summary.tasks} tasks');
      }
    } on BackupFormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not restore the backup.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _erase() async {
    final ok = await confirmDialog(
      context,
      title: 'Erase all data?',
      message: 'Every event and task will be permanently deleted and the '
          'default categories restored. Consider creating a backup first. '
          'This cannot be undone.',
      confirmLabel: 'Erase everything',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(backupControllerProvider).eraseAll();
      if (mounted) showSnack(context, 'All data erased');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(backupControllerProvider);
    final events = ref.watch(eventsProvider).length;
    final tasks = ref.watch(tasksProvider).length;
    final scheme = Theme.of(context).colorScheme;
    final stamp = _stamp();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & export'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ContentWidth(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  '$events events and $tasks tasks are stored on this device.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SectionHeader('Backup'),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Create backup'),
                subtitle: const Text(
                    'A JSON file with all events, tasks, categories and settings'),
                onTap: () => _export(
                  name: 'calendar-backup-$stamp.json',
                  mimeType: 'application/json',
                  build: controller.exportJson,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore from backup'),
                subtitle: const Text('Merge with or replace your current data'),
                onTap: _restore,
              ),
              const SectionHeader('Export'),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Export events as CSV'),
                subtitle: const Text('For spreadsheets'),
                onTap: () => _export(
                  name: 'calendar-events-$stamp.csv',
                  mimeType: 'text/csv',
                  build: controller.exportCsv,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('Export as iCalendar (.ics)'),
                subtitle: const Text('For other calendar apps'),
                onTap: () => _export(
                  name: 'calendar-$stamp.ics',
                  mimeType: 'text/calendar',
                  build: controller.exportIcs,
                ),
              ),
              const SectionHeader('Danger zone'),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                title: Text('Erase all data', style: TextStyle(color: scheme.error)),
                subtitle: const Text('Delete every event and task'),
                onTap: _erase,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
