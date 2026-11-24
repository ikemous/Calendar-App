import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/calendar_data.dart';
import '../providers/calendar_provider.dart';

/// Twelve mini months. Days with events are marked; tapping a month opens it.
class YearView extends ConsumerWidget {
  const YearView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final year = ref.watch(calendarProvider.select((s) => s.selected.year));
    final today = dateOnly(ref.watch(clockProvider)());
    final range = watchRange(ref, DateTime(year), DateTime(year + 1));

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w < 520 ? 2 : (w < 840 ? 3 : (w < 1200 ? 4 : 6));
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: 12,
          itemBuilder: (context, i) {
            final month = DateTime(year, i + 1);
            return _MiniMonth(
              month: month,
              today: today,
              firstDayOfWeek: settings.firstDayOfWeek,
              range: range,
              onTap: () {
                final controller = ref.read(calendarProvider.notifier);
                controller.select(isSameMonth(month, today) ? today : month);
                controller.setView(CalendarViewType.month);
              },
            );
          },
        );
      },
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.month,
    required this.today,
    required this.firstDayOfWeek,
    required this.range,
    required this.onTap,
  });

  final DateTime month;
  final DateTime today;
  final int firstDayOfWeek;
  final CalendarRange range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = monthGridDays(month, firstDayOfWeek);
    final isCurrent = isSameMonth(month, today);

    return Semantics(
      button: true,
      label: DateFormat.yMMMM().format(month),
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    DateFormat.MMMM().format(month),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                for (var w = 0; w < days.length ~/ 7; w++)
                  Expanded(
                    child: Row(
                      children: [
                        for (final day in days.skip(w * 7).take(7))
                          Expanded(child: _cell(day, theme)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(DateTime day, ThemeData theme) {
    if (!isSameMonth(day, month)) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final isToday = isSameDay(day, today);
    final busy = range.hasItems(day);
    return Center(
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isToday
              ? scheme.primary
              : (busy ? scheme.primaryContainer : null),
        ),
        child: FittedBox(
          child: Text(
            '${day.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: busy || isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday
                  ? scheme.onPrimary
                  : (busy ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
