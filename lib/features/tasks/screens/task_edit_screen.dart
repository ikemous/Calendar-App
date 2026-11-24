import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/config/app_config.dart';
import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/id.dart';
import '../../../data/models/calendar_event.dart' show Priority;
import '../../../data/models/task.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/reminder_dialogs.dart';
import '../../categories/providers/categories_provider.dart';
import '../../categories/widgets/category_picker.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/tasks_provider.dart';

/// Create or edit a task.
class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({super.key, this.taskId, this.initialDue});

  final String? taskId;
  final DateTime? initialDue;

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  Task? _original;
  DateTime? _due;
  bool _hasTime = false;
  Priority _priority = Priority.none;
  String? _categoryId;
  int? _reminder;
  bool _completed = false;
  bool _missing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final id = widget.taskId;
    if (id == null) {
      _due = widget.initialDue == null ? null : dateOnly(widget.initialDue!);
      return;
    }
    final task = ref.read(tasksProvider.notifier).byId(id);
    if (task == null) {
      _missing = true;
      return;
    }
    _original = task;
    _title.text = task.title;
    _description.text = task.description;
    _due = task.dueDate;
    _hasTime = task.hasDueTime;
    _priority = task.priority;
    _categoryId = task.categoryId;
    _reminder = task.reminderMinutes;
    _completed = task.completed;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: AppConfig.minDate,
      lastDate: AppConfig.maxDate,
    );
    if (picked == null) return;
    setState(() => _due = _hasTime && _due != null ? combine(picked, _due!) : picked);
  }

  Future<void> _pickTime() async {
    final base = _due ?? dateOnly(DateTime.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: _hasTime
          ? TimeOfDay.fromDateTime(base)
          : const TimeOfDay(hour: Task.defaultDueHour, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      _due = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
      _hasTime = true;
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = ref.read(clockProvider)();
    final original = _original;
    final due = _due;
    final task = Task(
      id: original?.id ?? newId(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      dueDate: due == null ? null : (_hasTime ? due : dateOnly(due)),
      hasDueTime: due != null && _hasTime,
      priority: _priority,
      categoryId: _categoryId,
      completed: _completed,
      completedAt: _completed ? (original?.completedAt ?? now) : null,
      reminderMinutes: due == null ? null : _reminder,
      createdAt: original?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      await ref.read(tasksProvider.notifier).save(task);
      if (!mounted) return;
      if (task.reminderMinutes != null && !task.completed) {
        await ensureNotificationPermission(context, ref);
        if (!mounted) return;
      }
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Could not save the task. Please try again.');
    }
  }

  Future<void> _delete() async {
    final task = _original;
    if (task == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete task?',
      message: '"${task.title}" will be permanently deleted.',
    );
    if (!ok || !mounted) return;
    context.pop();
    await ref.read(tasksProvider.notifier).delete(task.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.task_alt,
          title: 'Task not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final category = ref.watch(categoryMapProvider)[_categoryId];
    final due = _due;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(_original == null ? 'New task' : 'Edit task'),
        actions: [
          if (_original != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextFormField(
                controller: _title,
                autofocus: _original == null,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(hintText: 'Task'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Give the task a title'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Due date'),
                      subtitle: Text(due == null ? 'None' : formatDayShort(due)),
                      trailing: due == null
                          ? null
                          : IconButton(
                              tooltip: 'Clear due date',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _due = null;
                                _hasTime = false;
                                _reminder = null;
                              }),
                            ),
                      onTap: _pickDate,
                    ),
                    if (due != null) ...[
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('Due time'),
                        subtitle: Text(_hasTime
                            ? formatTime(due, settings.use24Hour)
                            : 'None'),
                        trailing: _hasTime
                            ? IconButton(
                                tooltip: 'Clear due time',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _hasTime = false;
                                  _due = dateOnly(due);
                                }),
                              )
                            : null,
                        onTap: _pickTime,
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Reminder'),
                        subtitle: Text(_reminder == null
                            ? 'None'
                            : _hasTime
                                ? formatReminder(_reminder!, subject: 'task')
                                : '${formatReminder(_reminder!, subject: 'task')} '
                                    '(from ${Task.defaultDueHour}:00)'),
                        onTap: () async {
                          final choice = await pickReminder(
                            context,
                            selected: _reminder,
                            allowNone: true,
                            subject: 'task',
                          );
                          if (choice != null) {
                            setState(() => _reminder = choice.minutes);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('Priority'),
                      subtitle: Text(_priority.label),
                      onTap: () async {
                        final p = await showOptionsDialog<Priority>(
                          context,
                          title: 'Priority',
                          options: Priority.values,
                          selected: _priority,
                          label: (p) => p.label,
                        );
                        if (p != null) setState(() => _priority = p);
                      },
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: CategoryBadge(category: category, size: 28),
                      title: const Text('Category'),
                      subtitle: Text(category?.name ?? 'None'),
                      onTap: () async {
                        final choice = await pickCategory(context, ref,
                            selectedId: _categoryId);
                        if (choice != null) {
                          setState(() => _categoryId = choice.id);
                        }
                      },
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.check_circle_outline),
                      title: const Text('Completed'),
                      value: _completed,
                      onChanged: (v) => setState(() => _completed = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
