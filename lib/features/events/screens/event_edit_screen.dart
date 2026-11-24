import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/config/app_config.dart';
import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/id.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/recurrence_rule.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/reminder_dialogs.dart';
import '../../calendar/services/recurrence_engine.dart';
import '../../categories/providers/categories_provider.dart';
import '../../categories/widgets/category_picker.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/events_provider.dart';
import '../services/series_editor.dart';
import '../widgets/recurrence_picker.dart';

/// Create or edit an event. When editing one occurrence of a recurring
/// event, the user is asked on save which part of the series to change.
class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({
    super.key,
    this.eventId,
    this.occurrenceStart,
    this.initialStart,
    this.initialAllDay = false,
  });

  final String? eventId;
  final DateTime? occurrenceStart;
  final DateTime? initialStart;
  final bool initialAllDay;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();

  CalendarEvent? _master;
  late DateTime _occurrenceStart;
  late DateTime _start;
  late DateTime _end;
  bool _allDay = false;
  String? _categoryId;
  int? _colorValue;
  Priority _priority = Priority.none;
  List<int> _reminders = [];
  RecurrenceRule? _recurrence;
  bool _dirty = false;
  bool _saving = false;
  bool _missing = false;

  bool get _isNew => _master == null;

  @override
  void initState() {
    super.initState();
    final id = widget.eventId;
    if (id != null) {
      final master = ref.read(eventsProvider.notifier).byId(id);
      if (master == null) {
        _missing = true;
        _occurrenceStart = _start = _end = DateTime.now();
        return;
      }
      _master = master;
      _occurrenceStart = widget.occurrenceStart ?? master.start;
      _start = _occurrenceStart;
      _end = RecurrenceEngine.endFor(master, _occurrenceStart);
      _allDay = master.allDay;
      _title.text = master.title;
      _location.text = master.location;
      _description.text = master.description;
      _notes.text = master.notes;
      _categoryId = master.categoryId;
      _colorValue = master.colorValue;
      _priority = master.priority;
      _reminders = [...master.reminders];
      _recurrence = master.recurrence;
    } else {
      final now = ref.read(clockProvider)();
      _start = widget.initialStart ??
          DateTime(now.year, now.month, now.day, now.hour + 1);
      _occurrenceStart = _start;
      _end = _start.add(const Duration(hours: 1));
      _allDay = widget.initialAllDay;
      final reminder = ref.read(settingsProvider).defaultReminderMinutes;
      _reminders = [?reminder];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _change(VoidCallback update) => setState(() {
        update();
        _dirty = true;
      });

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: AppConfig.minDate,
      lastDate: AppConfig.maxDate,
    );
    if (picked == null) return;
    _change(() {
      if (isStart) {
        // Moving the start keeps the event's length.
        final days = daysBetween(_start, picked);
        _start = combine(picked, _start);
        _end = addDays(_end, days);
      } else {
        _end = combine(picked, _end);
        if (_end.isBefore(_start)) _end = _start;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    _change(() {
      if (isStart) {
        final length = _end.difference(_start);
        _start = DateTime(
            _start.year, _start.month, _start.day, picked.hour, picked.minute);
        _end = _start.add(length);
      } else {
        _end = DateTime(
            _end.year, _end.month, _end.day, picked.hour, picked.minute);
        // An end time earlier than the start means "the next day".
        if (_end.isBefore(_start)) _end = addDays(_end, 1);
      }
    });
  }

  Future<void> _addReminder() async {
    final choice = await pickReminder(context);
    final minutes = choice?.minutes;
    if (minutes == null || _reminders.contains(minutes)) return;
    _change(() => _reminders = [..._reminders, minutes]..sort());
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final now = ref.read(clockProvider)();
    final master = _master;
    final start = _allDay ? dateOnly(_start) : _start;
    final end = _allDay ? dateOnly(_end) : _end;

    final edited = CalendarEvent(
      id: master?.id ?? newId(),
      title: _title.text.trim(),
      start: start,
      end: end.isBefore(start) ? start : end,
      allDay: _allDay,
      description: _description.text.trim(),
      notes: _notes.text.trim(),
      location: _location.text.trim(),
      categoryId: _categoryId,
      colorValue: _colorValue,
      priority: _priority,
      reminders: _reminders,
      recurrence: _recurrence,
      exDates: master?.exDates ?? const [],
      seriesId: master?.seriesId,
      originalStart: master?.originalStart,
      attachments: master?.attachments ?? const [],
      createdAt: master?.createdAt ?? now,
      updatedAt: now,
    );

    var scope = RecurrenceScope.all;
    if (master != null && master.isRecurring) {
      final picked = await pickScope(context, 'Save changes to');
      if (picked == null || !mounted) return;
      scope = picked;
    }

    setState(() => _saving = true);
    try {
      final events = ref.read(eventsProvider.notifier);
      if (master == null) {
        await events.save(edited);
      } else {
        await events.editOccurrence(
          master: master,
          occurrenceStart: _occurrenceStart,
          edited: edited,
          scope: scope,
        );
      }
      if (!mounted) return;
      if (edited.reminders.isNotEmpty) {
        await ensureNotificationPermission(context, ref);
        if (!mounted) return;
      }
      // `true` tells the detail page underneath to close as well: after an
      // edit the occurrence may have a new id or date.
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Could not save the event. Please try again.');
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your changes to this event have not been saved.',
      confirmLabel: 'Discard',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'Event not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final category = ref.watch(categoryMapProvider)[_categoryId];

    Widget dateRow(String label, DateTime value, {required bool isStart}) => Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => _pickDate(isStart: isStart),
                child: Text(formatDayShort(value)),
              ),
            ),
            if (!_allDay)
              TextButton(
                onPressed: () => _pickTime(isStart: isStart),
                child: Text(formatTime(value, settings.use24Hour)),
              ),
          ],
        );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(_isNew ? 'New event' : 'Edit event'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
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
                  autofocus: _isNew,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleLarge,
                  decoration: const InputDecoration(hintText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Give the event a title'
                      : null,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('All day'),
                          value: _allDay,
                          onChanged: (v) => _change(() => _allDay = v),
                        ),
                        dateRow('Starts', _start, isStart: true),
                        dateRow('Ends', _end, isStart: false),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.repeat),
                        title: const Text('Repeat'),
                        subtitle: Text(describeRecurrence(_recurrence)),
                        onTap: () async {
                          final choice = await pickRecurrence(
                            context,
                            current: _recurrence,
                            eventStart: _start,
                          );
                          if (choice != null) {
                            _change(() => _recurrence = choice.rule);
                          }
                        },
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Reminders'),
                        subtitle: _reminders.isEmpty
                            ? const Text('None')
                            : Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final m in _reminders)
                                      InputChip(
                                        label: Text(formatReminder(m)),
                                        onDeleted: () => _change(() =>
                                            _reminders = [
                                              for (final r in _reminders)
                                                if (r != m) r,
                                            ]),
                                      ),
                                  ],
                                ),
                              ),
                        trailing: IconButton(
                          tooltip: 'Add reminder',
                          icon: const Icon(Icons.add),
                          onPressed: _addReminder,
                        ),
                        onTap: _addReminder,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _location,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: CategoryBadge(category: category, size: 28),
                        title: const Text('Category'),
                        subtitle: Text(category?.name ?? 'None'),
                        onTap: () async {
                          final choice = await pickCategory(context, ref,
                              selectedId: _categoryId);
                          if (choice != null) {
                            _change(() => _categoryId = choice.id);
                          }
                        },
                      ),
                      const Divider(indent: 56),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Colour',
                                      style: theme.textTheme.bodyLarge),
                                ),
                                if (_colorValue != null)
                                  TextButton(
                                    onPressed: () =>
                                        _change(() => _colorValue = null),
                                    child: const Text('Use category colour'),
                                  ),
                              ],
                            ),
                            if (_colorValue == null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Using the category colour. Pick one to override.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ColorSwatchPicker(
                              selected: _colorValue,
                              onSelected: (c) =>
                                  _change(() => _colorValue = c),
                            ),
                          ],
                        ),
                      ),
                      const Divider(indent: 56),
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
                          if (p != null) _change(() => _priority = p);
                        },
                      ),
                    ],
                  ),
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
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
