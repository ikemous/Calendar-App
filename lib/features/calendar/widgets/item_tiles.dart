import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/task.dart';
import '../../../shared/utilities/event_style.dart';
import '../../categories/providers/categories_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../tasks/providers/tasks_provider.dart';

void openOccurrence(BuildContext context, EventOccurrence o) => context.push(
    '/event/${o.event.id}?occ=${o.start.millisecondsSinceEpoch}');

/// Time label for an occurrence as seen from [day] (which matters for
/// events that span several days).
String occurrenceTimeLabel(EventOccurrence o, DateTime day, bool use24Hour) {
  if (o.allDay) return 'All day';
  final startsToday = isSameDay(o.start, day);
  final endsToday = isSameDay(o.end, day);
  final start = formatTime(o.start, use24Hour);
  final end = formatTime(o.end, use24Hour);
  if (startsToday && endsToday) return o.start == o.end ? start : '$start – $end';
  if (startsToday) return '$start →';
  if (endsToday) return '→ $end';
  return 'All day';
}

/// Card for one event occurrence: colour, title, time and location.
class EventTile extends ConsumerWidget {
  const EventTile({
    super.key,
    required this.occurrence,
    required this.day,
    this.showDate = false,
    this.dense = false,
  });

  final EventOccurrence occurrence;

  /// The day this tile is listed under.
  final DateTime day;

  /// Prefix the time with the date (used by search results).
  final bool showDate;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final event = occurrence.event;
    final color = eventColor(event, ref.watch(categoryMapProvider), settings);
    final time = occurrenceTimeLabel(occurrence, day, settings.use24Hour);
    final when = showDate ? '${formatDayShort(occurrence.start)} · $time' : time;
    final title = event.title.isEmpty ? '(No title)' : event.title;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      label: [
        title,
        when,
        if (event.location.isNotEmpty) 'at ${event.location}',
      ].join(', '),
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: () => openOccurrence(context, occurrence),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: color),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: dense ? 8 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: dense ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        if (event.location.isNotEmpty && !dense) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.place_outlined, size: 14, color: muted),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  event.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: muted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (event.priority == Priority.high)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.priority_high,
                        size: 18, color: theme.colorScheme.error),
                  ),
                if (event.isRecurring)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(Icons.repeat, size: 16, color: muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Row for a task with a completion checkbox.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.showDue = true});

  final Task task;
  final bool showDue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final category = ref.watch(categoryMapProvider)[task.categoryId];
    final overdue = task.isOverdue(DateTime.now());
    final due = task.dueDate;

    final details = <String>[
      if (showDue && due != null)
        task.hasDueTime
            ? '${formatRelativeDay(due)}, ${formatTime(due, settings.use24Hour)}'
            : formatRelativeDay(due)
      else if (!showDue && due != null && task.hasDueTime)
        formatTime(due, settings.use24Hour),
      if (category != null) category.name,
    ];

    return Card(
      child: InkWell(
        onTap: () => context.push('/task/${task.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
          child: Row(
            children: [
              Checkbox(
                value: task.completed,
                shape: const CircleBorder(),
                semanticLabel: task.completed
                    ? 'Mark ${task.title} as not done'
                    : 'Mark ${task.title} as done',
                onChanged: (v) => ref
                    .read(tasksProvider.notifier)
                    .setCompleted(task, v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title.isEmpty ? '(No title)' : task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration:
                            task.completed ? TextDecoration.lineThrough : null,
                        color: task.completed ? scheme.outline : null,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: overdue ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (task.priority != Priority.none)
                Tooltip(
                  message: '${task.priority.label} priority',
                  child: Icon(Icons.flag,
                      size: 18, color: priorityColor(task.priority, scheme)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The events and tasks of one day as a column of tiles.
class DayItems extends StatelessWidget {
  const DayItems({
    super.key,
    required this.day,
    required this.occurrences,
    required this.tasks,
    this.dense = false,
  });

  final DateTime day;
  final List<EventOccurrence> occurrences;
  final List<Task> tasks;
  final bool dense;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in occurrences)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EventTile(occurrence: o, day: day, dense: dense),
            ),
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TaskTile(task: t, showDue: false),
            ),
        ],
      );
}
