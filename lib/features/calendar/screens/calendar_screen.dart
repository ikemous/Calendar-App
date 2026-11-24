import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/calendar_provider.dart';
import '../widgets/jump_to_date_sheet.dart';
import '../widgets/month_view.dart';
import '../widgets/time_grid_view.dart';
import '../widgets/year_view.dart';

const Map<CalendarViewType, IconData> _viewIcons = {
  CalendarViewType.month: Icons.calendar_view_month,
  CalendarViewType.week: Icons.calendar_view_week,
  CalendarViewType.day: Icons.calendar_view_day,
  CalendarViewType.year: Icons.calendar_today_outlined,
  CalendarViewType.agenda: Icons.view_agenda_outlined,
};

/// Start time suggested for a new event on [day]: the next full hour today,
/// or 9:00 on any other day.
DateTime suggestedStart(DateTime day, DateTime now) => isSameDay(day, now)
    ? DateTime(now.year, now.month, now.day, now.hour + 1)
    : DateTime(day.year, day.month, day.day, 9);

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  String _title(CalendarState s, int firstDayOfWeek) {
    final d = s.selected;
    switch (s.view) {
      case CalendarViewType.month:
        return DateFormat.yMMMM().format(d);
      case CalendarViewType.year:
        return '${d.year}';
      case CalendarViewType.day:
      case CalendarViewType.agenda:
        return DateFormat.yMMMEd().format(d);
      case CalendarViewType.week:
        final start = startOfWeek(d, firstDayOfWeek);
        final end = addDays(start, 6);
        final from = DateFormat.MMMd().format(start);
        final to = isSameMonth(start, end)
            ? '${end.day}'
            : DateFormat.MMMd().format(end);
        return '$from – $to, ${end.year}';
    }
  }

  String _pageKey(CalendarState s, int firstDayOfWeek) {
    final d = s.selected;
    return switch (s.view) {
      CalendarViewType.month => 'm${d.year}-${d.month}',
      CalendarViewType.year => 'y${d.year}',
      CalendarViewType.week =>
        'w${startOfWeek(d, firstDayOfWeek).millisecondsSinceEpoch}',
      _ => 'd${d.millisecondsSinceEpoch}',
    };
  }

  void _setView(BuildContext context, WidgetRef ref, CalendarViewType view) {
    if (view == CalendarViewType.agenda) {
      context.go('/agenda');
    } else {
      ref.read(calendarProvider.notifier).setView(view);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final firstDay =
        ref.watch(settingsProvider.select((s) => s.firstDayOfWeek));
    final controller = ref.read(calendarProvider.notifier);
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final unit = state.view.label.toLowerCase();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Semantics(
          button: true,
          label: '${_title(state, firstDay)}. Change date',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showJumpToDateSheet(context, state.selected);
              if (picked != null) controller.select(picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _title(state, firstDay),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<CalendarViewType>(
                showSelectedIcon: false,
                segments: [
                  for (final v in CalendarViewType.values)
                    ButtonSegment(value: v, label: Text(v.label)),
                ],
                selected: {state.view},
                onSelectionChanged: (s) => _setView(context, ref, s.first),
              ),
            ),
          IconButton(
            tooltip: 'Previous $unit',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => controller.page(-1),
          ),
          IconButton(
            tooltip: 'Next $unit',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => controller.page(1),
          ),
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: controller.goToToday,
          ),
          if (!wide)
            PopupMenuButton<CalendarViewType>(
              tooltip: 'Change view',
              icon: Icon(_viewIcons[state.view]),
              initialValue: state.view,
              onSelected: (v) => _setView(context, ref, v),
              itemBuilder: (context) => [
                for (final v in CalendarViewType.values)
                  PopupMenuItem(
                    value: v,
                    child: Row(
                      children: [
                        Icon(_viewIcons[v], size: 20),
                        const SizedBox(width: 12),
                        Text(v.label),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; unique tags stop them animating
        // into each other when a page opens on top.
        heroTag: 'fab-calendar',
        tooltip: 'New event',
        onPressed: () {
          final start = suggestedStart(state.selected, ref.read(clockProvider)());
          context.push('/event/new?start=${start.millisecondsSinceEpoch}');
        },
        child: const Icon(Icons.add),
      ),
      body: GestureDetector(
        // Swipe sideways to move between months, weeks, days or years.
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() < 250) return;
          controller.page(v < 0 ? 1 : -1);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey('${state.view.name}-${_pageKey(state, firstDay)}'),
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: switch (state.view) {
                CalendarViewType.month => const MonthView(),
                CalendarViewType.week => const TimeGridView(dayCount: 7),
                CalendarViewType.year => const YearView(),
                _ => const TimeGridView(dayCount: 1),
              },
            ),
          ),
        ),
      ),
    );
  }
}
