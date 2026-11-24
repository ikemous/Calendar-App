import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'theme/app_theme.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Calendar', Icons.calendar_month_outlined, Icons.calendar_month),
  _Destination('Agenda', Icons.view_agenda_outlined, Icons.view_agenda),
  _Destination('Tasks', Icons.check_circle_outline, Icons.check_circle),
  _Destination('Search', Icons.search, Icons.search),
  _Destination('Settings', Icons.settings_outlined, Icons.settings),
];

/// Top-level navigation: a bottom bar on phones, a rail on tablets and an
/// extended (labelled) rail on large landscape screens.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < kTabletBreakpoint) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }
    final extended = width >= 1100;
    return Scaffold(
      body: SafeArea(
        right: false,
        top: false,
        bottom: false,
        child: Row(
          children: [
            NavigationRail(
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      ),
    );
  }
}
