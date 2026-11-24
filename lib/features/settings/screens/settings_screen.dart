import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/notifications/lock_screen_planner.dart';
import '../../../core/services/file_service.dart';
import '../../../core/utilities/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/reminder_dialogs.dart';
import '../../categories/providers/categories_provider.dart';
import '../../events/providers/events_provider.dart';
import '../../sync/providers/sync_controller.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _themeLabels = {
    ThemeMode.system: 'System default',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  Future<void> _pickColor(
    BuildContext context, {
    required String title,
    required int? selected,
    required ValueChanged<int?> onPicked,
    bool allowDefault = false,
  }) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: ColorSwatchPicker(
              selected: selected,
              onSelected: (c) {
                onPicked(c);
                Navigator.of(context).pop();
              },
            ),
          ),
          actions: [
            if (allowDefault)
              TextButton(
                onPressed: () {
                  onPicked(null);
                  Navigator.of(context).pop();
                },
                child: const Text('Use accent colour'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final categoryCount = ref.watch(categoriesProvider).length;
    final sync = ref.watch(syncControllerProvider);
    final featured =
        LockScreenPlanner.featuredEvent(ref.watch(eventsProvider), s);

    final picture = s.lockScreenImagePath;

    Future<void> setPicture(String? path) async {
      final old = s.lockScreenImagePath;
      await notifier.change((s) => s.copyWith(lockScreenImagePath: () => path));
      if (old != null && old != path) {
        await ref.read(fileServiceProvider).deleteLockScreenImage(old);
      }
    }

    Future<void> choosePicture() async {
      try {
        final path = await ref.read(fileServiceProvider).pickLockScreenImage();
        if (path != null) await setPicture(path);
      } on FormatException {
        if (context.mounted) showSnack(context, 'That file is not a picture');
      } catch (_) {
        if (context.mounted) showSnack(context, 'Could not open the picture');
      }
    }

    Widget swatch(int color) => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionHeader('Appearance'),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Theme'),
              subtitle: Text(_themeLabels[s.themeMode]!),
              onTap: () async {
                final mode = await showOptionsDialog<ThemeMode>(
                  context,
                  title: 'Theme',
                  options: ThemeMode.values,
                  selected: s.themeMode,
                  label: (m) => _themeLabels[m]!,
                );
                if (mode != null) notifier.change((s) => s.copyWith(themeMode: mode));
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Accent colour'),
              subtitle: const Text('Used for the app theme'),
              trailing: swatch(s.seedColor),
              onTap: () => _pickColor(
                context,
                title: 'Accent colour',
                selected: s.seedColor,
                onPicked: (c) {
                  if (c != null) notifier.change((s) => s.copyWith(seedColor: c));
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.format_color_fill),
              title: const Text('Default event colour'),
              subtitle: const Text('For events without a category or colour'),
              trailing: swatch(s.defaultEventColor ?? s.seedColor),
              onTap: () => _pickColor(
                context,
                title: 'Default event colour',
                selected: s.defaultEventColor,
                allowDefault: true,
                onPicked: (c) =>
                    notifier.change((s) => s.copyWith(defaultEventColor: () => c)),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.short_text),
              title: const Text('Event titles in month view'),
              subtitle: const Text('Turn off to show compact dots instead'),
              value: s.showEventTitlesInMonth,
              onChanged: (v) =>
                  notifier.change((s) => s.copyWith(showEventTitlesInMonth: v)),
            ),
            const SectionHeader('Calendar'),
            ListTile(
              leading: const Icon(Icons.view_carousel_outlined),
              title: const Text('Default view'),
              subtitle: Text(s.defaultView.label),
              onTap: () async {
                final view = await showOptionsDialog<CalendarViewType>(
                  context,
                  title: 'Default view',
                  options: CalendarViewType.values,
                  selected: s.defaultView,
                  label: (v) => v.label,
                );
                if (view != null) {
                  notifier.change((s) => s.copyWith(defaultView: view));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_outlined),
              title: const Text('First day of the week'),
              subtitle: Text(weekdayLabelsLong[s.firstDayOfWeek - 1]),
              onTap: () async {
                final day = await showOptionsDialog<int>(
                  context,
                  title: 'First day of the week',
                  options: const [
                    DateTime.monday,
                    DateTime.sunday,
                    DateTime.saturday,
                  ],
                  selected: s.firstDayOfWeek,
                  label: (d) => weekdayLabelsLong[d - 1],
                );
                if (day != null) {
                  notifier.change((s) => s.copyWith(firstDayOfWeek: day));
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.access_time),
              title: const Text('24-hour time'),
              subtitle: Text(s.use24Hour ? '13:00' : '1:00 PM'),
              value: s.use24Hour,
              onChanged: (v) => notifier.change((s) => s.copyWith(use24Hour: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.checklist),
              title: const Text('Show tasks in calendar'),
              value: s.showTasksInCalendar,
              onChanged: (v) =>
                  notifier.change((s) => s.copyWith(showTasksInCalendar: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.done_all),
              title: const Text('Show completed tasks in calendar'),
              value: s.showCompletedTasks,
              onChanged: s.showTasksInCalendar
                  ? (v) => notifier.change((s) => s.copyWith(showCompletedTasks: v))
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Categories'),
              subtitle: Text('$categoryCount categories'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/categories'),
            ),
            const SectionHeader('Notifications'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Reminders'),
              subtitle: const Text('Notify me about events and tasks'),
              value: s.notificationsEnabled,
              onChanged: (v) async {
                await notifier.change((s) => s.copyWith(notificationsEnabled: v));
                if (v && context.mounted) {
                  await ensureNotificationPermission(context, ref, force: true);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.alarm),
              title: const Text('Default reminder'),
              subtitle: Text(s.defaultReminderMinutes == null
                  ? 'None'
                  : formatReminder(s.defaultReminderMinutes!)),
              onTap: () async {
                final choice = await pickReminder(
                  context,
                  selected: s.defaultReminderMinutes,
                  allowNone: true,
                );
                if (choice != null) {
                  notifier.change((s) => s.copyWith(
                      defaultReminderMinutes: () => choice.minutes));
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.lock_clock_outlined),
              title: const Text('Next event on lock screen'),
              subtitle: Text(s.notificationsEnabled
                  ? featured == null
                      ? 'Count down to my next event'
                      : 'Used when no event is featured'
                  : 'Turn on Reminders to use this'),
              value: s.notificationsEnabled && s.showNextEventOnLockScreen,
              onChanged: s.notificationsEnabled
                  ? (v) async {
                      await notifier.change(
                          (s) => s.copyWith(showNextEventOnLockScreen: v));
                      if (v && context.mounted) {
                        await ensureNotificationPermission(
                          context,
                          ref,
                          force: true,
                          title: lockScreenPermissionTitle,
                          message: lockScreenPermissionMessage,
                        );
                      }
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Featured event on lock screen'),
              subtitle: Text(featured == null
                  ? 'None. Open a repeating event and tap the pin'
                  : (featured.title.isEmpty ? '(No title)' : featured.title)),
              trailing: featured == null
                  ? null
                  : IconButton(
                      tooltip: 'Stop featuring',
                      icon: const Icon(Icons.close),
                      onPressed: () => notifier.setFeatured(featured.id, false),
                    ),
              onTap: featured == null
                  ? null
                  : () => context.push('/event/${featured.id}'),
            ),
            ListTile(
              leading: picture == null
                  ? const Icon(Icons.image_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(picture),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
              title: const Text('Lock screen picture'),
              subtitle: Text(picture == null
                  ? 'Choose a picture to show beside the featured event'
                  : 'Shown beside the featured event'),
              trailing: picture == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove picture',
                      icon: const Icon(Icons.close),
                      onPressed: () => setPicture(null),
                    ),
              onTap: choosePicture,
            ),
            const SectionHeader('Accounts'),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Google Calendar'),
              subtitle: Text(sync.connected
                  ? (sync.error ?? 'Syncing with ${sync.account}')
                  : 'Not connected'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/google'),
            ),
            const SectionHeader('Data'),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Backup, restore and export'),
              subtitle: const Text('JSON backup, CSV and iCalendar export'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/backup'),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy'),
              subtitle: const Text('How your data is stored'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/privacy'),
            ),
            const SectionHeader('About'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: const Text('Version and licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/about'),
            ),
          ],
        ),
      ),
    );
  }
}
