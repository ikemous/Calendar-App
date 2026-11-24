import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_services.dart';
import '../../../core/utilities/date_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';

/// What the calendar screen is showing: which view and which date.
class CalendarState {
  const CalendarState({required this.view, required this.selected});

  final CalendarViewType view;

  /// The selected day (always a local midnight).
  final DateTime selected;

  CalendarState copyWith({CalendarViewType? view, DateTime? selected}) =>
      CalendarState(
        view: view ?? this.view,
        selected: selected ?? this.selected,
      );
}

class CalendarController extends Notifier<CalendarState> {
  @override
  CalendarState build() {
    // read (not watch): changing the default view in settings should not
    // reset the calendar the user is currently looking at.
    final preferred = ref.read(settingsProvider).defaultView;
    return CalendarState(
      view: preferred == CalendarViewType.agenda
          ? CalendarViewType.month
          : preferred,
      selected: dateOnly(ref.read(clockProvider)()),
    );
  }

  void setView(CalendarViewType view) => state = state.copyWith(view: view);

  void select(DateTime day) => state = state.copyWith(selected: dateOnly(day));

  void goToToday() => select(ref.read(clockProvider)());

  /// Opens the day view on [day].
  void openDay(DateTime day) =>
      state = CalendarState(view: CalendarViewType.day, selected: dateOnly(day));

  /// Moves one page (month, week, day or year) forward or back.
  void page(int direction) {
    final d = state.selected;
    state = state.copyWith(
      selected: switch (state.view) {
        CalendarViewType.month => addMonths(d, direction),
        CalendarViewType.week => addDays(d, 7 * direction),
        CalendarViewType.day || CalendarViewType.agenda => addDays(d, direction),
        CalendarViewType.year => addMonths(d, 12 * direction),
      },
    );
  }
}

final calendarProvider =
    NotifierProvider<CalendarController, CalendarState>(CalendarController.new);
