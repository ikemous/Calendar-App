import 'package:material_ui/material_ui.dart' show ThemeMode;

enum CalendarViewType {
  month('Month'),
  week('Week'),
  day('Day'),
  year('Year'),
  agenda('Agenda');

  const CalendarViewType(this.label);
  final String label;
}

/// User preferences. Persisted as key/value rows.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.defaultView = CalendarViewType.month,
    this.firstDayOfWeek = DateTime.monday,
    this.use24Hour = false,
    this.defaultReminderMinutes = 15,
    this.notificationsEnabled = true,
    this.seedColor = 0xFF3F6FD8,
    this.showTasksInCalendar = true,
    this.showCompletedTasks = true,
    this.showEventTitlesInMonth = true,
    this.defaultEventColor,
    this.showNextEventOnLockScreen = true,
    this.featuredEventId,
    this.lockScreenImagePath,
  });

  final ThemeMode themeMode;
  final CalendarViewType defaultView;

  /// [DateTime.monday]..[DateTime.sunday].
  final int firstDayOfWeek;
  final bool use24Hour;

  /// Reminder pre-selected for new events; null = none.
  final int? defaultReminderMinutes;
  final bool notificationsEnabled;

  /// Accent colour the Material 3 colour scheme is generated from.
  final int seedColor;
  final bool showTasksInCalendar;
  final bool showCompletedTasks;

  /// Month view: show event titles (true) or compact dots (false).
  final bool showEventTitlesInMonth;

  /// Colour for events with no category and no own colour; null = accent.
  final int? defaultEventColor;

  /// Keep the next upcoming event in a persistent lock screen notification.
  final bool showNextEventOnLockScreen;

  /// The one repeating event the user features on the lock screen.
  final String? featuredEventId;

  /// Picture shown beside the featured event on the lock screen: the path
  /// of a small copy in the app's private storage. Null = no image.
  final String? lockScreenImagePath;

  AppSettings copyWith({
    ThemeMode? themeMode,
    CalendarViewType? defaultView,
    int? firstDayOfWeek,
    bool? use24Hour,
    int? Function()? defaultReminderMinutes,
    bool? notificationsEnabled,
    int? seedColor,
    bool? showTasksInCalendar,
    bool? showCompletedTasks,
    bool? showEventTitlesInMonth,
    int? Function()? defaultEventColor,
    bool? showNextEventOnLockScreen,
    String? Function()? featuredEventId,
    String? Function()? lockScreenImagePath,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        defaultView: defaultView ?? this.defaultView,
        firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
        use24Hour: use24Hour ?? this.use24Hour,
        defaultReminderMinutes: defaultReminderMinutes != null
            ? defaultReminderMinutes()
            : this.defaultReminderMinutes,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        seedColor: seedColor ?? this.seedColor,
        showTasksInCalendar: showTasksInCalendar ?? this.showTasksInCalendar,
        showCompletedTasks: showCompletedTasks ?? this.showCompletedTasks,
        showEventTitlesInMonth:
            showEventTitlesInMonth ?? this.showEventTitlesInMonth,
        defaultEventColor: defaultEventColor != null
            ? defaultEventColor()
            : this.defaultEventColor,
        showNextEventOnLockScreen:
            showNextEventOnLockScreen ?? this.showNextEventOnLockScreen,
        featuredEventId:
            featuredEventId != null ? featuredEventId() : this.featuredEventId,
        lockScreenImagePath: lockScreenImagePath != null
            ? lockScreenImagePath()
            : this.lockScreenImagePath,
      );

  Map<String, String> toMap() => {
        'themeMode': themeMode.name,
        'defaultView': defaultView.name,
        'firstDayOfWeek': '$firstDayOfWeek',
        'use24Hour': '$use24Hour',
        'defaultReminderMinutes': defaultReminderMinutes?.toString() ?? '',
        'notificationsEnabled': '$notificationsEnabled',
        'seedColor': '$seedColor',
        'showTasksInCalendar': '$showTasksInCalendar',
        'showCompletedTasks': '$showCompletedTasks',
        'showEventTitlesInMonth': '$showEventTitlesInMonth',
        'defaultEventColor': defaultEventColor?.toString() ?? '',
        'showNextEventOnLockScreen': '$showNextEventOnLockScreen',
        'featuredEventId': featuredEventId ?? '',
        'lockScreenImagePath': lockScreenImagePath ?? '',
      };

  factory AppSettings.fromMap(Map<String, String> m) {
    const d = AppSettings();
    bool flag(String k, bool fallback) =>
        m.containsKey(k) ? m[k] == 'true' : fallback;
    T pick<T extends Enum>(List<T> values, String k, T fallback) =>
        values.firstWhere((v) => v.name == m[k], orElse: () => fallback);
    final first = int.tryParse(m['firstDayOfWeek'] ?? '');
    return AppSettings(
      themeMode: pick(ThemeMode.values, 'themeMode', d.themeMode),
      defaultView: pick(CalendarViewType.values, 'defaultView', d.defaultView),
      firstDayOfWeek:
          (first != null && first >= 1 && first <= 7) ? first : d.firstDayOfWeek,
      use24Hour: flag('use24Hour', d.use24Hour),
      defaultReminderMinutes: m.containsKey('defaultReminderMinutes')
          ? int.tryParse(m['defaultReminderMinutes']!)
          : d.defaultReminderMinutes,
      notificationsEnabled: flag('notificationsEnabled', d.notificationsEnabled),
      seedColor: int.tryParse(m['seedColor'] ?? '') ?? d.seedColor,
      showTasksInCalendar: flag('showTasksInCalendar', d.showTasksInCalendar),
      showCompletedTasks: flag('showCompletedTasks', d.showCompletedTasks),
      showEventTitlesInMonth:
          flag('showEventTitlesInMonth', d.showEventTitlesInMonth),
      defaultEventColor: int.tryParse(m['defaultEventColor'] ?? ''),
      showNextEventOnLockScreen: flag(
          'showNextEventOnLockScreen', d.showNextEventOnLockScreen),
      featuredEventId:
          (m['featuredEventId'] ?? '').isEmpty ? null : m['featuredEventId'],
      lockScreenImagePath: (m['lockScreenImagePath'] ?? '').isEmpty
          ? null
          : m['lockScreenImagePath'],
    );
  }
}
