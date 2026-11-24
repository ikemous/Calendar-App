import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/notifications/lock_screen_planner.dart';
import '../../../core/services/app_services.dart';
import '../../../core/utilities/formatters.dart';
import '../../../data/models/calendar_event.dart';
import '../../../shared/utilities/event_style.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/reminder_dialogs.dart';
import '../../calendar/services/recurrence_engine.dart';
import '../../categories/providers/categories_provider.dart';
import '../../categories/widgets/category_picker.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/events_provider.dart';
import '../services/series_editor.dart';
import '../widgets/recurrence_picker.dart';

/// Read-only view of one event occurrence with edit and delete actions.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.occurrenceStart,
  });

  final String eventId;
  final DateTime? occurrenceStart;

  Future<void> _delete(
      BuildContext context, WidgetRef ref, CalendarEvent event, DateTime start) async {
    var scope = RecurrenceScope.all;
    if (event.isRecurring) {
      final picked = await pickScope(context, 'Delete');
      if (picked == null) return;
      scope = picked;
    } else {
      final ok = await confirmDialog(
        context,
        title: 'Delete event?',
        message: '"${event.title}" will be permanently deleted.',
      );
      if (!ok) return;
    }
    if (!context.mounted) return;
    // Leave the page first so it does not rebuild around a missing event.
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    await ref.read(eventsProvider.notifier).deleteOccurrence(
          master: event,
          occurrenceStart: start,
          scope: scope,
        );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Event deleted')));
  }

  Future<void> _toggleFeatured(
      BuildContext context, WidgetRef ref, CalendarEvent event) async {
    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    if (settings.featuredEventId == event.id) {
      await notifier.setFeatured(event.id, false);
      if (context.mounted) showSnack(context, 'Removed from the lock screen');
      return;
    }
    if (!settings.notificationsEnabled) {
      showSnack(context, 'Turn on Reminders in Settings to use the lock screen');
      return;
    }
    final now = ref.read(clockProvider)();
    if (LockScreenPlanner.currentOccurrence(event, now) == null) {
      showSnack(context, 'This event is already over');
      return;
    }
    final replaced =
        LockScreenPlanner.featuredEvent(ref.read(eventsProvider), settings);
    await notifier.setFeatured(event.id, true);
    if (!context.mounted) return;
    final allowed = await ensureNotificationPermission(
      context,
      ref,
      force: true,
      title: lockScreenPermissionTitle,
      message: lockScreenPermissionMessage,
    );
    if (allowed && context.mounted) {
      showSnack(
        context,
        replaced == null
            ? 'Featured on the lock screen'
            : 'Featured on the lock screen instead of "${replaced.title}"',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(categoryMapProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    CalendarEvent? event;
    for (final e in events) {
      if (e.id == eventId) event = e;
    }
    if (event == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'Event not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    final e = event;
    final start = occurrenceStart ?? e.start;
    final end = RecurrenceEngine.endFor(e, start);
    final color = eventColor(e, categories, settings);
    final category = categories[e.categoryId];
    final query = '?occ=${start.millisecondsSinceEpoch}';
    final featured = settings.featuredEventId == e.id;

    Widget row(IconData icon, String title, {String? subtitle, Widget? leading}) =>
        ListTile(
          leading: leading ?? Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
        );

    Widget block(String label, String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.primary)),
              const SizedBox(height: 6),
              SelectableText(text, style: theme.textTheme.bodyLarge),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        actions: [
          // The featured slot is for one repeating event.
          if (e.isRecurring || featured)
            IconButton(
              tooltip: featured
                  ? 'Remove from lock screen'
                  : 'Feature on lock screen',
              isSelected: featured,
              icon: const Icon(Icons.push_pin_outlined),
              selectedIcon: const Icon(Icons.push_pin),
              onPressed: () => _toggleFeatured(context, ref, e),
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final changed =
                  await context.push<bool>('/event/${e.id}/edit$query');
              if (changed == true && context.mounted) context.pop();
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref, e, start),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(top: 8, right: 14),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.title.isEmpty ? '(No title)' : e.title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            row(
              Icons.schedule,
              formatRange(start, end,
                  allDay: e.allDay, use24Hour: settings.use24Hour),
              subtitle: e.isRecurring ? describeRecurrence(e.recurrence) : null,
            ),
            if (e.location.isNotEmpty) row(Icons.place_outlined, e.location),
            if (category != null)
              row(Icons.label_outline, category.name,
                  leading: CategoryBadge(category: category, size: 26)),
            if (e.reminders.isNotEmpty)
              row(
                Icons.notifications_outlined,
                e.reminders.map(formatReminder).join('\n'),
              ),
            if (e.priority != Priority.none)
              row(
                Icons.flag_outlined,
                '${e.priority.label} priority',
                leading:
                    Icon(Icons.flag, color: priorityColor(e.priority, scheme)),
              ),
            if (featured)
              row(Icons.push_pin_outlined, 'Featured on the lock screen',
                  subtitle: 'Always shows its next occurrence'),
            if (e.description.isNotEmpty) block('Description', e.description),
            if (e.notes.isNotEmpty) block('Notes', e.notes),
          ],
        ),
      ),
    );
  }
}
