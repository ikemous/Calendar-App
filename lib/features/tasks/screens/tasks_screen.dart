import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../data/models/task.dart';
import '../../../shared/widgets/common.dart';
import '../../calendar/widgets/item_tiles.dart';
import '../providers/tasks_provider.dart';

enum _Filter { active, all, completed }

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  _Filter _filter = _Filter.active;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final today = dateOnly(now);
    final all = [...ref.watch(tasksProvider)]..sort(compareTasks);
    final tasks = switch (_filter) {
      _Filter.active => all.where((t) => !t.completed).toList(),
      _Filter.completed => all.where((t) => t.completed).toList(),
      _Filter.all => all,
    };

    // Group into sections, in display order.
    final sections = <String, List<Task>>{};
    for (final t in tasks) {
      final due = t.dueDate;
      final section = t.completed
          ? 'Completed'
          : due == null
              ? 'No date'
              : t.isOverdue(now)
                  ? 'Overdue'
                  : isSameDay(due, today)
                      ? 'Today'
                      : 'Upcoming';
      (sections[section] ??= []).add(t);
    }
    const order = ['Overdue', 'Today', 'Upcoming', 'No date', 'Completed'];

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; unique tags stop them animating
        // into each other when a page opens on top.
        heroTag: 'fab-tasks',
        tooltip: 'New task',
        onPressed: () => context.push('/task/new'),
        child: const Icon(Icons.add),
      ),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_Filter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Filter.active, label: Text('To do')),
                    ButtonSegment(value: _Filter.all, label: Text('All')),
                    ButtonSegment(value: _Filter.completed, label: Text('Done')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? EmptyState(
                      icon: Icons.task_alt,
                      title: switch (_filter) {
                        _Filter.active => 'All caught up',
                        _Filter.completed => 'No completed tasks yet',
                        _Filter.all => 'No tasks yet',
                      },
                      message: _filter == _Filter.completed
                          ? null
                          : 'Tap + to add a task.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                      children: [
                        for (final name in order)
                          if (sections[name] != null) ...[
                            SectionHeader(
                              '$name · ${sections[name]!.length}',
                              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                            ),
                            for (final t in sections[name]!)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _DismissibleTask(task: t),
                              ),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Task row that can be swiped away, with an undo.
class _DismissibleTask extends ConsumerWidget {
  const _DismissibleTask({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        final notifier = ref.read(tasksProvider.notifier);
        notifier.delete(task.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Task deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => notifier.save(task),
            ),
          ));
      },
      child: TaskTile(task: task),
    );
  }
}
