import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/settings/providers/settings_provider.dart';
import 'config/app_config.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class CalendarApp extends ConsumerWidget {
  const CalendarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final seed = Color(settings.seedColor);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      themeMode: settings.themeMode,
      theme: AppTheme.build(Brightness.light, seed),
      darkTheme: AppTheme.build(Brightness.dark, seed),
      builder: (context, child) => MediaQuery(
        // Make system time pickers follow the app's 12/24-hour setting.
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: settings.use24Hour),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
