/// A reminder to be delivered by the operating system at [when].
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String payload;
}

/// A silent, persistent notification that keeps an event visible on the
/// lock screen between [showAt] and [hideAt].
class LockScreenCard {
  const LockScreenCard({
    required this.id,
    required this.label,
    required this.title,
    required this.body,
    required this.hideAt,
    required this.payload,
    this.showAt,
  });

  final int id;

  /// Short heading, e.g. "Next event".
  final String label;
  final String title;
  final String body;

  /// When the card appears; null means straight away.
  final DateTime? showAt;

  /// When the card removes itself (Android; see `LocalNotificationService`).
  final DateTime hideAt;
  final String payload;
}

/// What a tapped notification points at.
class NotificationTarget {
  const NotificationTarget.event(this.id, this.occurrenceStart) : isTask = false;
  const NotificationTarget.task(this.id)
      : isTask = true,
        occurrenceStart = null;

  final String id;
  final bool isTask;
  final DateTime? occurrenceStart;

  String encode() => isTask
      ? 'task|$id'
      : 'event|$id|${occurrenceStart?.millisecondsSinceEpoch ?? ''}';

  static NotificationTarget? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final parts = payload.split('|');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    if (parts[0] == 'task') return NotificationTarget.task(parts[1]);
    if (parts[0] != 'event') return null;
    final ms = parts.length > 2 ? int.tryParse(parts[2]) : null;
    return NotificationTarget.event(
      parts[1],
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// In-app route for this target.
  String get route {
    if (isTask) return '/task/$id';
    final occ = occurrenceStart;
    return occ == null
        ? '/event/$id'
        : '/event/$id?occ=${occ.millisecondsSinceEpoch}';
  }
}

/// Platform-independent notification API. The app depends only on this, so
/// the plugin-backed implementation can be swapped (and faked in tests).
abstract interface class NotificationService {
  /// Prepares the service. [onTap] is called with the payload of a
  /// notification the user taps while the app is running.
  Future<void> init({required void Function(String payload) onTap});

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload();

  Future<bool> hasPermission();

  /// Shows the system permission prompt if needed.
  Future<bool> requestPermission();

  Future<void> schedule(ScheduledReminder reminder);

  /// Shows [card] now, or hands it to the OS to show at its `showAt`.
  /// Showing a card whose id is already on screen updates it in place.
  Future<void> showCard(LockScreenCard card, {required DateTime now});

  /// Cancels everything pending and on screen, except notifications on
  /// screen whose id is in [keep].
  Future<void> cancelAll({Set<int> keep = const {}});
}

/// Used where notifications are unavailable (unsupported platforms, tests).
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<void> init({required void Function(String payload) onTap}) async {}

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(ScheduledReminder reminder) async {}

  @override
  Future<void> showCard(LockScreenCard card, {required DateTime now}) async {}

  @override
  Future<void> cancelAll({Set<int> keep = const {}}) async {}
}
