import 'calendar_event.dart' show Priority;

/// A to-do item, optionally due on a date (and time).
class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.dueDate,
    this.hasDueTime = false,
    this.priority = Priority.none,
    this.categoryId,
    this.completed = false,
    this.completedAt,
    this.reminderMinutes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String description;

  /// Due date. The clock part is only meaningful when [hasDueTime] is true.
  final DateTime? dueDate;
  final bool hasDueTime;
  final Priority priority;
  final String? categoryId;
  final bool completed;
  final DateTime? completedAt;

  /// Minutes before the due moment to notify; null = no reminder.
  final int? reminderMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Hour used as the "due moment" for tasks that have a date but no time.
  static const int defaultDueHour = 9;

  /// The instant reminders are measured from.
  DateTime? get dueMoment {
    final d = dueDate;
    if (d == null) return null;
    return hasDueTime ? d : DateTime(d.year, d.month, d.day, defaultDueHour);
  }

  bool isOverdue(DateTime now) {
    final d = dueDate;
    if (completed || d == null) return false;
    final deadline =
        hasDueTime ? d : DateTime(d.year, d.month, d.day + 1);
    return deadline.isBefore(now);
  }

  Task copyWith({
    String? title,
    String? description,
    DateTime? Function()? dueDate,
    bool? hasDueTime,
    Priority? priority,
    String? Function()? categoryId,
    bool? completed,
    DateTime? Function()? completedAt,
    int? Function()? reminderMinutes,
    DateTime? updatedAt,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        dueDate: dueDate != null ? dueDate() : this.dueDate,
        hasDueTime: hasDueTime ?? this.hasDueTime,
        priority: priority ?? this.priority,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        completed: completed ?? this.completed,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
        reminderMinutes:
            reminderMinutes != null ? reminderMinutes() : this.reminderMinutes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'due_ms': dueDate?.millisecondsSinceEpoch,
        'has_due_time': hasDueTime ? 1 : 0,
        'priority': priority.index,
        'category_id': categoryId,
        'completed': completed ? 1 : 0,
        'completed_ms': completedAt?.millisecondsSinceEpoch,
        'reminder_minutes': reminderMinutes,
        'created_ms': createdAt.millisecondsSinceEpoch,
        'updated_ms': updatedAt.millisecondsSinceEpoch,
      };

  factory Task.fromMap(Map<String, Object?> m) {
    DateTime? ms(String k) {
      final v = (m[k] as num?)?.toInt();
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return Task(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      dueDate: ms('due_ms'),
      hasDueTime: (m['has_due_time'] as num?)?.toInt() == 1,
      priority: Priority.fromIndex((m['priority'] as num?)?.toInt()),
      categoryId: m['category_id'] as String?,
      completed: (m['completed'] as num?)?.toInt() == 1,
      completedAt: ms('completed_ms'),
      reminderMinutes: (m['reminder_minutes'] as num?)?.toInt(),
      createdAt: ms('created_ms') ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: ms('updated_ms') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
