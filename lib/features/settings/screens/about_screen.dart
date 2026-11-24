import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/config/app_config.dart';
import '../../../shared/widgets/common.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      if (mounted) setState(() => _version = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.calendar_month,
                    size: 44, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(AppConfig.appName,
                  style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'A private, offline calendar',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Version'),
              subtitle: Text(_version),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppConfig.appName,
                applicationVersion: _version,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
