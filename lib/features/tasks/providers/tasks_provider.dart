import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/services/app_services.dart';
import '../../../data/models/task.dart';
import '../../sync/providers/sync_controller.dart';

class TasksNotifier extends Notifier<List<Task>> {
  @override
  List<Task> build() => ref.watch(bootstrapProvider).tasks;

  Task? byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> save(Task task) async {
    await ref.read(taskRepositoryProvider).upsert(task);
    await ref.read(syncServiceProvider).recordChanged('tasks', task.id);
    state = [
      for (final t in state)
        if (t.id != task.id) t,
      task,
    ];
    await ref.read(reminderSchedulerProvider).sync();
  }

  Future<void> setCompleted(Task task, bool completed) {
    final now = ref.read(clockProvider)();
    return save(task.copyWith(
      completed: completed,
      completedAt: () => completed ? now : null,
      updatedAt: now,
    ));
  }

  Future<void> delete(String id) async {
    await ref.read(taskRepositoryProvider).delete(id);
    await ref.read(syncServiceProvider).recordDeleted('tasks', id);
    state = [
      for (final t in state)
        if (t.id != id) t,
    ];
    await ref.read(reminderSchedulerProvider).sync();
  }

  Future<void> reload() async {
    state = await ref.read(taskRepositoryProvider).getAll();
  }
}

final tasksProvider =
    NotifierProvider<TasksNotifier, List<Task>>(TasksNotifier.new);

/// Display order: incomplete first, then by due date (undated last), then
/// by priority and title.
int compareTasks(Task a, Task b) {
  if (a.completed != b.completed) return a.completed ? 1 : -1;
  final ad = a.dueDate, bd = b.dueDate;
  if (ad == null && bd != null) return 1;
  if (ad != null && bd == null) return -1;
  if (ad != null && bd != null) {
    final c = ad.compareTo(bd);
    if (c != 0) return c;
  }
  final p = b.priority.index.compareTo(a.priority.index);
  if (p != 0) return p;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}
