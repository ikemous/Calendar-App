import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/utilities/event_style.dart';
import '../../../shared/widgets/common.dart';
import '../../categories/providers/categories_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/calendar_data.dart';
import '../providers/calendar_provider.dart';
import 'item_tiles.dart';

class _Chip {
  const _Chip(this.label, this.color, {this.isTask = false, this.done = false});
  final String label;
  final Color color;
  final bool isTask;
  final bool done;
}

/// Month grid with the selected day's events alongside (wide screens) or
/// underneath (phones).
class MonthView extends ConsumerWidget {
  const MonthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final selected = ref.watch(calendarProvider.select((s) => s.selected));
    final categories = ref.watch(categoryMapProvider);
    final today = dateOnly(ref.watch(clockProvider)());
    final scheme = Theme.of(context).colorScheme;

    final days = monthGridDays(selected, settings.firstDayOfWeek);
    final range = watchRange(ref, days.first, addDays(days.last, 1));

    List<_Chip> chipsFor(DateTime day) => [
          for (final o in range.occurrencesOn(day))
            _Chip(
              o.event.title.isEmpty ? '(No title)' : o.event.title,
              eventColor(o.event, categories, settings),
            ),
          for (final t in range.tasksOn(day))
            _Chip(t.title, scheme.outline, isTask: true, done: t.completed),
        ];

    final grid = Column(
      children: [
        _WeekdayHeader(firstDayOfWeek: settings.firstDayOfWeek),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < days.length ~/ 7; w++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final day in days.skip(w * 7).take(7))
                        Expanded(
                          child: _DayCell(
                            day: day,
                            inMonth: isSameMonth(day, selected),
                            isToday: isSameDay(day, today),
                            isSelected: isSameDay(day, selected),
                            chips: chipsFor(day),
                            showTitles: settings.showEventTitlesInMonth,
                            onTap: () {
                              final controller =
                                  ref.read(calendarProvider.notifier);
                              // Tapping the selected day again opens it.
                              isSameDay(day, selected)
                                  ? controller.openDay(day)
                                  : controller.select(day);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final panel = _SelectedDayPanel(day: selected, range: range);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kWideBreakpoint) {
          return Row(
            children: [
              Expanded(child: grid),
              const VerticalDivider(width: 1),
              SizedBox(width: 340, child: panel),
            ],
          );
        }
        // Short screens (phones in landscape) show the grid only.
        if (constraints.maxHeight < 440) return grid;
        return Column(
          children: [
            Expanded(flex: 11, child: grid),
            const Divider(height: 1),
            Expanded(flex: 8, child: panel),
          ],
        );
      },
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.firstDayOfWeek});
  final int firstDayOfWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (final wd in orderedWeekdays(firstDayOfWeek))
            Expanded(
              child: Text(
                weekdayLabelsShort[wd - 1],
                textAlign: TextAlign.center,
                semanticsLabel: weekdayLabelsLong[wd - 1],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.chips,
    required this.showTitles,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<_Chip> chips;
  final bool showTitles;
  final VoidCallback onTap;

  static const double _numberHeight = 28;
  static const double _chipHeight = 17;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = chips.length;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${formatDayLong(day)}, '
          '${count == 0 ? 'no items' : '$count item${count == 1 ? '' : 's'}'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primaryContainer.withValues(alpha: 0.45)
                : null,
            border: Border(
              top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final room = constraints.maxHeight - _numberHeight;
              final titles = showTitles && room >= _chipHeight;
              final fit = (room / _chipHeight).floor();
              final visible = count <= fit ? count : (fit - 1).clamp(0, count);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: _numberHeight,
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isToday ? scheme.primary : null,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${day.day}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight:
                                isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isToday
                                ? scheme.onPrimary
                                : inMonth
                                    ? scheme.onSurface
                                    : scheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (titles) ...[
                    for (final c in chips.take(visible))
                      _ChipBar(chip: c, faded: !inMonth, height: _chipHeight),
                    if (count > visible)
                      SizedBox(
                        height: _chipHeight,
                        child: Text(
                          '+${count - visible}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ] else if (count > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final c in chips.take(4))
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: c.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChipBar extends StatelessWidget {
  const _ChipBar({required this.chip, required this.faded, required this.height});
  final _Chip chip;
  final bool faded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = chip.isTask
        ? Colors.transparent
        : chip.color.withValues(alpha: faded ? 0.45 : 1);
    final foreground =
        chip.isTask ? theme.colorScheme.onSurfaceVariant : onColor(chip.color);
    return Container(
      height: height - 2,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: chip.isTask
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (chip.isTask)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                chip.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 9,
                color: foreground,
              ),
            ),
          Expanded(
            child: Text(
              chip.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                height: 1.1,
                color: foreground,
                decoration: chip.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDayPanel extends StatelessWidget {
  const _SelectedDayPanel({required this.day, required this.range});
  final DateTime day;
  final CalendarRange range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occurrences = range.occurrencesOn(day);
    final tasks = range.tasksOn(day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            formatDayLong(day),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: occurrences.isEmpty && tasks.isEmpty
              ? const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Nothing planned',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  children: [
                    DayItems(
                      day: day,
                      occurrences: occurrences,
                      tasks: tasks,
                      dense: true,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
