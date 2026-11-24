import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/common.dart';
import '../../events/providers/events_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/sync_controller.dart';
import '../services/calendar_auth.dart';
import '../services/device_calendar.dart';

/// Connect, sync and disconnect Google Calendar.
class GoogleSyncScreen extends ConsumerStatefulWidget {
  const GoogleSyncScreen({super.key});

  @override
  ConsumerState<GoogleSyncScreen> createState() => _GoogleSyncScreenState();
}

class _GoogleSyncScreenState extends ConsumerState<GoogleSyncScreen> {
  bool _connecting = false;

  /// Phone-calendar mode: asks for calendar access and lets the user pick
  /// the calendar to sync with. Returns it, or null if they backed out.
  Future<DeviceCalendarInfo?> _pickCalendar(DeviceCalendarAuth auth) async {
    final List<DeviceCalendarInfo>? calendars;
    try {
      calendars = await auth.loadCalendars();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not read the phone\'s calendars.');
      return null;
    }
    if (!mounted) return null;
    if (calendars == null) {
      showSnack(context,
          'Calendar access is needed to sync. You can allow it in system settings.');
      return null;
    }
    if (calendars.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No calendars on this phone'),
          content: const Text(
            'Add your Google account in the phone\'s Settings → Passwords & '
            'accounts, make sure Calendar sync is switched on for it, then '
            'come back and connect.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }
    return showDialog<DeviceCalendarInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sync with which calendar?'),
        children: [
          for (final c in calendars!)
            ListTile(
              leading: Icon(Icons.circle,
                  color: c.color == null ? null : Color(c.color! | 0xFF000000)),
              title: Text(c.name),
              subtitle: Text(c.isGoogle
                  ? '${c.account} · Google'
                  : c.account.isEmpty
                      ? 'On this phone only'
                      : c.account),
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    final auth = ref.read(calendarAuthProvider);
    var target = 'your main Google calendar';
    var targetShort = 'your Google Calendar';
    if (auth is DeviceCalendarAuth) {
      final calendar = await _pickCalendar(auth);
      if (calendar == null || !mounted) return;
      auth.choose(calendar);
      target = 'the "${calendar.name}" calendar';
      targetShort = 'that calendar';
    }
    final localCount = ref.read(eventsProvider).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sync),
        title: const Text('Connect Google Calendar?'),
        content: Text(
          'Events in $target will appear in this app, and '
          '${localCount == 0 ? 'events you create here' : 'the $localCount events already in this app'} '
          'will be added to $targetShort.\n\n'
          'After that, changes and deletions made in either place are '
          'copied to the other. Tasks are not synced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _connecting = true);
    try {
      await ref.read(syncControllerProvider.notifier).connect();
    } on CalendarAuthException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (_) {
      if (mounted) {
        showSnack(
            context,
            auth is DeviceCalendarAuth
                ? 'Could not connect to the calendar.'
                : 'Could not sign in to Google.');
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirmDialog(
      context,
      title: 'Disconnect Google Calendar?',
      message: 'Syncing stops. Your events stay in this app and in Google '
          'Calendar; nothing is deleted.',
      confirmLabel: 'Disconnect',
      destructive: false,
    );
    if (ok) await ref.read(syncControllerProvider.notifier).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    final use24Hour = ref.watch(settingsProvider.select((s) => s.use24Hour));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final last = status.lastSync;
    final result = status.lastResult;
    final onPhone = controller.usesDeviceCalendar;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Calendar'),
        bottom: status.syncing || _connecting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (!status.connected) ...[
              Icon(Icons.sync, size: 56, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Two-way sync',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                onPhone
                    ? 'Keep this app in step with a calendar on this phone, '
                        'such as your Google calendar. No sign-in is needed: '
                        'the phone already syncs that calendar with Google.'
                    : 'Keep this app and your main Google calendar in step. '
                        'Events created, changed or deleted in one appear in '
                        'the other.',
                style: muted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (controller.isConfigured)
                FilledButton.icon(
                  icon: Icon(onPhone ? Icons.event_available : Icons.login),
                  label: Text(onPhone
                      ? 'Choose a calendar to sync'
                      : 'Connect Google account'),
                  onPressed: _connecting ? null : _connect,
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Google sync is not set up in this build. The '
                            'app needs Google client IDs before it can sign '
                            'in; see docs/GOOGLE_CALENDAR_SYNC.md.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ] else ...[
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(status.account!),
                      subtitle: Text(
                        status.syncing
                            ? 'Syncing…'
                            : last == null
                                ? 'Not synced yet'
                                : 'Last synced ${formatRelativeDay(last)}, '
                                    '${formatTime(last, use24Hour)}',
                      ),
                    ),
                    if (status.error != null)
                      ListTile(
                        leading: Icon(Icons.error_outline, color: scheme.error),
                        title: Text(status.error!,
                            style: TextStyle(color: scheme.error)),
                      ),
                    if (result != null && status.error == null)
                      ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(
                          '${result.pulled} received, ${result.pushed} sent, '
                          '${result.removedLocally + result.removedRemotely} removed',
                        ),
                        subtitle: result.unsupportedRepeats == 0
                            ? null
                            : Text(
                                '${result.unsupportedRepeats} events repeat in '
                                'a way this app cannot show. Only their first '
                                'date appears here; they are unchanged in '
                                '${onPhone ? 'the calendar' : 'Google Calendar'}.',
                              ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
                onPressed: status.syncing ? null : controller.syncNow,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: status.syncing ? null : _disconnect,
                child: const Text('Disconnect'),
              ),
            ],
            const SizedBox(height: 28),
            Text('How it works', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              onPhone
                  ? '• Syncs with the calendar you choose on this phone. If '
                      'it belongs to your Google account, the phone passes '
                      'changes on to Google Calendar and back.\n'
                      '• Runs when you open the app, after you change an '
                      'event, and when you tap Sync now. The phone then '
                      'syncs with Google on its own schedule, usually within '
                      'a few minutes.\n'
                      '• If the same event was changed in both places, the '
                      'change made in this app is kept.\n'
                      '• Notes, priority, colour and category stay in this '
                      'app only.\n'
                      '• Tasks stay on this device.'
                  : '• Syncs your main ("primary") Google calendar.\n'
                      '• Runs when you open the app, after you change an '
                      'event, and when you tap Sync now. It does not run '
                      'while the app is closed.\n'
                      '• If the same event was changed in both places, the '
                      'most recent change is kept.\n'
                      '• Notes, priority, colour and category are stored '
                      'with the event in Google but only this app shows '
                      'them.\n'
                      '• Tasks stay on this device.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}
