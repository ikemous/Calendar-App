import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/services/app_services.dart';
import '../../../data/models/app_settings.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(bootstrapProvider).settings;

  Future<void> change(AppSettings Function(AppSettings) change) async {
    final previous = state;
    final next = change(previous);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
    // Notification text and scheduling depend on these settings.
    if (previous.notificationsEnabled != next.notificationsEnabled ||
        previous.use24Hour != next.use24Hour ||
        previous.showNextEventOnLockScreen != next.showNextEventOnLockScreen ||
        previous.featuredEventId != next.featuredEventId ||
        previous.lockScreenImagePath != next.lockScreenImagePath) {
      await ref.read(reminderSchedulerProvider).sync();
    }
  }

  /// Makes [eventId] the featured lock screen event (replacing any other),
  /// or stops featuring it.
  Future<void> setFeatured(String eventId, bool featured) => change((s) {
        if (featured) return s.copyWith(featuredEventId: () => eventId);
        return s.featuredEventId == eventId
            ? s.copyWith(featuredEventId: () => null)
            : s;
      });

  Future<void> reload() async {
    state = await ref.read(settingsRepositoryProvider).load();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
