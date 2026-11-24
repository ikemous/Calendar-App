import 'package:material_ui/material_ui.dart';

import '../../../shared/widgets/common.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget point(IconData icon, String title, String body) => ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(body),
          ),
          isThreeLine: true,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            point(
              Icons.phone_iphone,
              'Your calendar stays on this device',
              'Events, tasks and settings are stored in a private database '
                  'that only this app can read. Nothing is uploaded unless '
                  'you connect Google Calendar.',
            ),
            point(
              Icons.person_off_outlined,
              'No account, no tracking',
              'The app works without signing in and does not collect '
                  'analytics or advertising data.',
            ),
            point(
              Icons.wifi_off,
              'Works offline',
              'The calendar works without an internet connection. The '
                  'network is used only for Google Calendar sync, if you '
                  'turn it on.',
            ),
            point(
              Icons.sync,
              'Calendar sync is optional',
              'If you connect a calendar on this phone, the app asks for '
                  'calendar access and copies events to and from that '
                  'calendar. Other calendar apps on the phone can then see '
                  'them, and the phone syncs them to the account the '
                  'calendar belongs to, such as Google. Tasks are not synced. '
                  'Disconnect at any time in Settings.',
            ),
            point(
              Icons.notifications_outlined,
              'Notifications',
              'Permission is requested only when you add a reminder or put '
                  'an event on the lock screen. Reminders and lock screen '
                  'events are created on the device and show the title, time '
                  'and location, never the description or notes. Anyone who '
                  'can see your locked phone can read them; turn off "Next '
                  'event on lock screen" in Settings if you prefer.',
            ),
            point(
              Icons.ios_share,
              'Exports are in your hands',
              'Backups and exports are created only when you ask, and go '
                  'only where you choose to save or share them. Backup files '
                  'are not encrypted, so store them somewhere safe.',
            ),
            point(
              Icons.delete_outline,
              'Deleting your data',
              'Use "Erase all data" under Backup & export, or uninstall the '
                  'app, to remove everything.',
            ),
          ],
        ),
      ),
    );
  }
}
