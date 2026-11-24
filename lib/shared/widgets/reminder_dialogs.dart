import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/notifications/reminder_scheduler.dart';
import '../../core/services/app_services.dart';
import '../../core/utilities/formatters.dart';
import '../../features/settings/providers/settings_provider.dart';
import 'common.dart';

/// Result of the reminder picker. [minutes] null means "no reminder".
class ReminderChoice {
  const ReminderChoice(this.minutes);
  final int? minutes;
}

const String lockScreenPermissionTitle = 'Allow notifications?';
const String lockScreenPermissionMessage =
    'Events are kept on the lock screen as a silent notification, so the '
    'app needs permission to show notifications.';

/// Lets the user choose a reminder offset: a preset, a custom value, or
/// (when [allowNone]) no reminder. Returns null if dismissed.
Future<ReminderChoice?> pickReminder(
  BuildContext context, {
  int? selected,
  bool allowNone = false,
  String subject = 'event',
}) async {
  const custom = -1;
  const none = -2;
  final choice = await showOptionsDialog<int>(
    context,
    title: 'Reminder',
    options: [if (allowNone) none, ...reminderPresets, custom],
    selected: selected ?? (allowNone ? none : null),
    label: (m) => switch (m) {
      custom => 'Custom…',
      none => 'None',
      _ => formatReminder(m, subject: subject),
    },
  );
  if (choice == null || !context.mounted) return null;
  if (choice == none) return const ReminderChoice(null);
  if (choice != custom) return ReminderChoice(choice);
  final minutes = await _customReminder(context);
  return minutes == null ? null : ReminderChoice(minutes);
}

Future<int?> _customReminder(BuildContext context) => showDialog<int>(
      context: context,
      builder: (context) => const _CustomReminderDialog(),
    );

class _CustomReminderDialog extends StatefulWidget {
  const _CustomReminderDialog();

  @override
  State<_CustomReminderDialog> createState() => _CustomReminderDialogState();
}

class _CustomReminderDialogState extends State<_CustomReminderDialog> {
  final _controller = TextEditingController(text: '45');
  int _unit = 1; // minutes per unit

  static const _units = {1: 'minutes', 60: 'hours', 1440: 'days', 10080: 'weeks'};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_controller.text);
    if (n == null || n < 0) return;
    Navigator.of(context).pop(n * _unit);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Custom reminder'),
        content: Row(
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textAlign: TextAlign.center,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _unit,
                items: [
                  for (final e in _units.entries)
                    DropdownMenuItem(value: e.key, child: Text('${e.value} before')),
                ],
                onChanged: (v) => setState(() => _unit = v ?? 1),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Add')),
        ],
      );
}

class _PromptState {
  bool declined = false;
}

final _promptStateProvider = Provider<_PromptState>((ref) => _PromptState());

/// Makes sure the app may post notifications before a reminder is saved.
/// Explains why first, then shows the system prompt. Returns whether
/// notifications are allowed; saving proceeds either way.
///
/// If the user answers "Not now", they are not asked again until the app is
/// restarted, unless [force] is set (used when they explicitly turn
/// reminders on in settings).
Future<bool> ensureNotificationPermission(
  BuildContext context,
  WidgetRef ref, {
  bool force = false,
  String title = 'Allow reminders?',
  String message =
      'To remind you about this at the time you chose, the app needs '
      'permission to show notifications. Reminders are created on this '
      'device only.',
}) async {
  if (!ref.read(settingsProvider).notificationsEnabled) return false;
  final service = ref.read(notificationServiceProvider);
  if (await service.hasPermission()) return true;
  final prompt = ref.read(_promptStateProvider);
  if (prompt.declined && !force) return false;
  if (!context.mounted) return false;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (proceed != true) {
    prompt.declined = true;
    return false;
  }
  final granted = await service.requestPermission();
  if (granted) {
    // Anything scheduled before permission existed needs scheduling again.
    await ref.read(reminderSchedulerProvider).sync();
  } else if (context.mounted) {
    showSnack(context,
        'Notifications are off. You can allow them in system settings.');
  }
  return granted;
}
