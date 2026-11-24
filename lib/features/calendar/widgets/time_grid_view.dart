import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/task.dart';
import '../../../shared/utilities/event_style.dart';
import '../../categories/providers/categories_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/calendar_data.dart';
import '../providers/calendar_provider.dart';
import '../services/overlap_layout.dart';
import 'item_tiles.dart';

const double _hourHeight = 56;
const double _gutter = 52;

/// Hour-by-hour grid used by the day view ([dayCount] 1) and the week view
/// ([dayCount] 7). All-day and multi-day events sit in a band above the
/// grid; simultaneous timed events are laid out side by side.
class TimeGridView extends ConsumerStatefulWidget {
  const TimeGridView({super.key, required this.dayCount});
  final int dayCount;

  @override
  ConsumerState<TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends ConsumerState<TimeGridView> {
  late final ScrollController _scroll;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    final hour = (now.hour - 1).clamp(0, 16);
    _scroll = ScrollController(initialScrollOffset: hour * _hourHeight);
    // Keep the "now" line moving.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final selected = ref.watch(calendarProvider.select((s) => s.selected));
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final first = widget.dayCount == 1
        ? selected
        : startOfWeek(selected, settings.firstDayOfWeek);
    final days = [for (var i = 0; i < widget.dayCount; i++) addDays(first, i)];
    final range = watchRange(ref, first, addDays(first, widget.dayCount));

    // All-day events go in the band above the grid. Timed events that run
    // past midnight are drawn in the grid, one segment per day.
    bool inBand(EventOccurrence o) => o.allDay;

    return Column(
      children: [
        // Day headers.
        Padding(
          padding: const EdgeInsets.only(left: _gutter, top: 4, bottom: 4),
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _DayHeader(
                    day: day,
                    isToday: isSameDay(day, now),
                    isSelected: isSameDay(day, selected),
                    wide: widget.dayCount == 1,
                    onTap: () => widget.dayCount == 1
                        ? null
                        : ref.read(calendarProvider.notifier).openDay(day),
                  ),
                ),
            ],
          ),
        ),
        // All-day band.
        if (days.any((d) =>
            range.occurrencesOn(d).any(inBand) || range.tasksOn(d).isNotEmpty))
          Container(
            constraints: const BoxConstraints(maxHeight: 132),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 6),
                      child: Text(
                        'All day',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  for (final day in days)
                    Expanded(
                      child: _AllDayColumn(
                        occurrences:
                            range.occurrencesOn(day).where(inBand).toList(),
                        tasks: range.tasksOn(day),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Hour grid.
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: _hourHeight * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: _HourLabels(use24Hour: settings.use24Hour),
                  ),
                  for (final day in days)
                    Expanded(
                      child: _DayColumn(
                        day: day,
                        now: isSameDay(day, now) ? now : null,
                        occurrences: range
                            .occurrencesOn(day)
                            .where((o) => !inBand(o))
                            .toList(),
                        compact: widget.dayCount > 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.wide,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday
            ? scheme.primary
            : (isSelected && !wide ? scheme.primaryContainer : null),
      ),
      child: Text(
        '${day.day}',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isToday ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    );
    final label = Text(
      wide ? weekdayLabelsLong[day.weekday - 1] : weekdayLabelsShort[day.weekday - 1],
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: theme.textTheme.labelSmall?.copyWith(
        color: isToday ? scheme.primary : scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
    return Semantics(
      button: !wide,
      label: formatDayLong(day),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: wide ? null : onTap,
        child: wide
            ? Row(children: [number, const SizedBox(width: 8), label])
            : Column(children: [label, const SizedBox(height: 2), number]),
      ),
    );
  }
}

class _AllDayColumn extends ConsumerWidget {
  const _AllDayColumn({required this.occurrences, required this.tasks});
  final List<EventOccurrence> occurrences;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(categoryMapProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 3, 1, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in occurrences)
            _Pill(
              label: o.event.title.isEmpty ? '(No title)' : o.event.title,
              color: eventColor(o.event, categories, settings),
              onTap: () => openOccurrence(context, o),
            ),
          for (final t in tasks)
            _Pill(
              label: t.title,
              icon: t.completed
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: theme.colorScheme.surfaceContainerHighest,
              struck: t.completed,
              onTap: () => context.push('/task/${t.id}'),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.struck = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final bool struck;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                children: [
                  if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(icon, size: 11, color: onColor(color)),
                    ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: onColor(color),
                            decoration:
                                struck ? TextDecoration.lineThrough : null,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _HourLabels extends StatelessWidget {
  const _HourLabels({required this.use24Hour});
  final bool use24Hour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Stack(
        children: [
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * _hourHeight - 7,
              right: 6,
              child: Text(
                use24Hour
                    ? '${h.toString().padLeft(2, '0')}:00'
                    : '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.day,
    required this.now,
    required this.occurrences,
    required this.compact,
  });

  final DateTime day;

  /// Current time when [day] is today, otherwise null.
  final DateTime? now;
  final List<EventOccurrence> occurrences;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(categoryMapProvider);
    final scheme = Theme.of(context).colorScheme;

    final placed = layoutOverlaps<EventOccurrence>(
      occurrences,
      // Only the part of the event that falls on this day is drawn: an
      // event that began earlier starts at the top, and one that continues
      // (or ends at midnight) runs to the bottom.
      startMinute: (o) =>
          isSameDay(o.start, day) ? o.start.hour * 60 + o.start.minute : 0,
      endMinute: (o) =>
          isSameDay(o.end, day) ? o.end.hour * 60 + o.end.minute : 1440,
      minDuration: 25,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            // Tap an empty slot to create an event at that hour.
            final hour = (details.localPosition.dy / _hourHeight).floor().clamp(0, 23);
            final start = DateTime(day.year, day.month, day.day, hour);
            context.push('/event/new?start=${start.millisecondsSinceEpoch}');
          },
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    line: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              for (final p in placed)
                Positioned(
                  top: p.startMinute / 60 * _hourHeight,
                  left: width * p.column / p.columns,
                  width: width / p.columns - 2,
                  height: ((p.endMinute.clamp(0, 1440) - p.startMinute) /
                              60 *
                              _hourHeight -
                          1)
                      .clamp(18, _hourHeight * 24),
                  child: _EventBlock(
                    occurrence: p.item,
                    color: eventColor(p.item.event, categories, settings),
                    use24Hour: settings.use24Hour,
                    compact: compact,
                  ),
                ),
              if (now != null)
                Positioned(
                  top: (now!.hour * 60 + now!.minute) / 60 * _hourHeight - 1,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(height: 2, color: scheme.error),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({
    required this.occurrence,
    required this.color,
    required this.use24Hour,
    required this.compact,
  });

  final EventOccurrence occurrence;
  final Color color;
  final bool use24Hour;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = occurrence.event;
    final foreground = onColor(color);
    final title = event.title.isEmpty ? '(No title)' : event.title;
    final time = formatTime(occurrence.start, use24Hour);
    return Semantics(
      button: true,
      label: '$title, $time',
      excludeSemantics: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openOccurrence(context, occurrence),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final roomy = constraints.maxHeight >= 40;
              return Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 3 : 6, vertical: roomy ? 3 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: roomy && constraints.maxHeight >= 64 ? 2 : 1,
                        overflow: TextOverflow.clip,
                        softWrap: roomy && constraints.maxHeight >= 64,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (roomy && !compact)
                      Flexible(
                        child: Text(
                          event.location.isEmpty
                              ? time
                              : '$time · ${event.location}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: foreground.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.line});
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * _hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.line != line;
}
