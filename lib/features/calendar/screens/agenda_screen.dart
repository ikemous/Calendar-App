import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/common.dart';
import '../providers/calendar_data.dart';
import '../widgets/item_tiles.dart';
import 'calendar_screen.dart' show suggestedStart;

/// Chronological list of upcoming events and tasks, grouped by day.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  static const int _step = 90;

  /// How many days ahead (and optionally back) are listed.
  int _daysAhead = _step;
  int _daysBack = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateOnly(ref.watch(clockProvider)());
    final from = addDays(today, -_daysBack);
    final to = addDays(today, _daysAhead);
    final range = watchRange(ref, from, to);

    final days = [
      for (var d = from; d.isBefore(to); d = addDays(d, 1))
        if (range.hasItems(d)) d,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            tooltip: _daysBack == 0 ? 'Show past 30 days' : 'Hide past days',
            icon: Icon(_daysBack == 0 ? Icons.history : Icons.history_toggle_off),
            onPressed: () => setState(() => _daysBack = _daysBack == 0 ? 30 : 0),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; unique tags stop them animating
        // into each other when a page opens on top.
        heroTag: 'fab-agenda',
        tooltip: 'New event',
        onPressed: () {
          final start = suggestedStart(today, ref.read(clockProvider)());
          context.push('/event/new?start=${start.millisecondsSinceEpoch}');
        },
        child: const Icon(Icons.add),
      ),
      body: ContentWidth(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
          itemCount: days.length + 1,
          itemBuilder: (context, i) {
            if (i == days.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    if (days.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 48, bottom: 8),
                        child: EmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'Nothing coming up',
                          message: 'Events and dated tasks will appear here.',
                        ),
                      ),
                    Text(
                      'Showing through ${formatDayShort(addDays(to, -1))}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _daysAhead += _step),
                      child: const Text('Load more'),
                    ),
                  ],
                ),
              );
            }
            final day = days[i];
            final isToday = isSameDay(day, today);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      switch (daysBetween(today, day)) {
                        0 => 'Today · ${formatDayShort(day)}',
                        1 => 'Tomorrow · ${formatDayShort(day)}',
                        _ => formatDayShort(day),
                      },
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                DayItems(
                  day: day,
                  occurrences: range.occurrencesOn(day),
                  tasks: range.tasksOn(day),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
