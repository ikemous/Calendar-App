import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/config/app_config.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../data/models/recurrence_rule.dart';
import '../services/series_editor.dart';

/// Result of the repeat picker. [rule] null means "does not repeat".
class RecurrenceChoice {
  const RecurrenceChoice(this.rule);
  final RecurrenceRule? rule;
}

String describeRecurrence(RecurrenceRule? rule) {
  if (rule == null) return 'Does not repeat';
  if (rule == RecurrenceRule.biweekly) return 'Every two weeks';
  return rule.describe();
}

/// Lets the user choose how an event repeats. Returns null if dismissed.
Future<RecurrenceChoice?> pickRecurrence(
  BuildContext context, {
  required RecurrenceRule? current,
  required DateTime eventStart,
}) async {
  const presets = <(String, RecurrenceRule?)>[
    ('Does not repeat', null),
    ('Daily', RecurrenceRule.daily),
    ('Weekly', RecurrenceRule.weekly),
    ('Every two weeks', RecurrenceRule.biweekly),
    ('Monthly', RecurrenceRule.monthly),
    ('Yearly', RecurrenceRule.yearly),
  ];
  final isCustom = current != null && !presets.any((p) => p.$2 == current);
  final index = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Repeat'),
      children: [
        for (var i = 0; i <= presets.length; i++)
          Builder(builder: (context) {
            final custom = i == presets.length;
            final selected =
                custom ? isCustom : (!isCustom && presets[i].$2 == current);
            return ListTile(
              leading: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(custom ? 'Custom…' : presets[i].$1),
              subtitle: custom && isCustom ? Text(current.describe()) : null,
              onTap: () => Navigator.of(context).pop(i),
            );
          }),
      ],
    ),
  );
  if (index == null || !context.mounted) return null;
  if (index < presets.length) return RecurrenceChoice(presets[index].$2);
  final rule = await showDialog<RecurrenceRule>(
    context: context,
    builder: (context) => _CustomRecurrenceDialog(
      initial: current ?? RecurrenceRule.weekly,
      eventStart: eventStart,
    ),
  );
  return rule == null ? null : RecurrenceChoice(rule);
}

/// Asks which part of a recurring series an action applies to.
Future<RecurrenceScope?> pickScope(BuildContext context, String title) =>
    showDialog<RecurrenceScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final s in RecurrenceScope.values)
            ListTile(
              title: Text(s.label),
              onTap: () => Navigator.of(context).pop(s),
            ),
        ],
      ),
    );

enum _End { never, onDate, afterCount }

class _CustomRecurrenceDialog extends StatefulWidget {
  const _CustomRecurrenceDialog({required this.initial, required this.eventStart});
  final RecurrenceRule initial;
  final DateTime eventStart;

  @override
  State<_CustomRecurrenceDialog> createState() => _CustomRecurrenceDialogState();
}

class _CustomRecurrenceDialogState extends State<_CustomRecurrenceDialog> {
  late RecurrenceFrequency _frequency = widget.initial.frequency;
  late final _interval =
      TextEditingController(text: '${widget.initial.interval}');
  late final _count =
      TextEditingController(text: '${widget.initial.count ?? 10}');
  late Set<int> _weekdays = widget.initial.weekdays.isEmpty
      ? {widget.eventStart.weekday}
      : {...widget.initial.weekdays};
  late _End _end = widget.initial.until != null
      ? _End.onDate
      : (widget.initial.count != null ? _End.afterCount : _End.never);
  late DateTime _until =
      widget.initial.until ?? addMonths(dateOnly(widget.eventStart), 3);

  @override
  void dispose() {
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  void _submit() {
    final interval = (int.tryParse(_interval.text) ?? 1).clamp(1, 999);
    final count = (int.tryParse(_count.text) ?? 1).clamp(1, 999);
    Navigator.of(context).pop(RecurrenceRule(
      frequency: _frequency,
      interval: interval,
      weekdays: _frequency == RecurrenceFrequency.weekly ? _weekdays : const {},
      until: _end == _End.onDate ? _until : null,
      count: _end == _End.afterCount ? count : null,
    ));
  }

  Widget _number(TextEditingController controller) => SizedBox(
        width: 72,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const units = {
      RecurrenceFrequency.daily: 'day(s)',
      RecurrenceFrequency.weekly: 'week(s)',
      RecurrenceFrequency.monthly: 'month(s)',
      RecurrenceFrequency.yearly: 'year(s)',
    };
    return AlertDialog(
      title: const Text('Custom repeat'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Every'),
                  const SizedBox(width: 12),
                  _number(_interval),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<RecurrenceFrequency>(
                      initialValue: _frequency,
                      items: [
                        for (final f in RecurrenceFrequency.values)
                          DropdownMenuItem(value: f, child: Text(units[f]!)),
                      ],
                      onChanged: (f) =>
                          setState(() => _frequency = f ?? _frequency),
                    ),
                  ),
                ],
              ),
              if (_frequency == RecurrenceFrequency.weekly) ...[
                const SizedBox(height: 16),
                Text('On', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var wd = 1; wd <= 7; wd++)
                      FilterChip(
                        label: Text(weekdayLabelsShort[wd - 1]),
                        selected: _weekdays.contains(wd),
                        showCheckmark: false,
                        onSelected: (on) => setState(() {
                          final next = {..._weekdays};
                          on ? next.add(wd) : next.remove(wd);
                          // At least one weekday must stay selected.
                          if (next.isNotEmpty) _weekdays = next;
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Ends', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<_End>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _End.never, label: Text('Never')),
                  ButtonSegment(value: _End.onDate, label: Text('On date')),
                  ButtonSegment(value: _End.afterCount, label: Text('After')),
                ],
                selected: {_end},
                onSelectionChanged: (s) => setState(() => _end = s.first),
              ),
              if (_end == _End.onDate)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(formatDayShort(_until)),
                    onPressed: () async {
                      final first = dateOnly(widget.eventStart);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _until.isBefore(first) ? first : _until,
                        firstDate: first,
                        lastDate: AppConfig.maxDate,
                      );
                      if (picked != null) setState(() => _until = picked);
                    },
                  ),
                ),
              if (_end == _End.afterCount)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      _number(_count),
                      const SizedBox(width: 12),
                      const Text('occurrences'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}
