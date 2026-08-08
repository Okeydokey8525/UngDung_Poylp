import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    _Destination('Tổng quan', Icons.dashboard_outlined, Icons.dashboard),
    _Destination('Phân tích', Icons.image_search_outlined, Icons.image_search),
    _Destination('So sánh', Icons.compare_outlined, Icons.compare),
    _Destination('Lịch sử', Icons.history_outlined, Icons.history),
    _Destination('Tài khoản', Icons.person_outline, Icons.person),
  ];

  void _selectDestination(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = navigationShell.currentIndex;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final content = SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: navigationShell,
            ),
          ),
        );
        if (width < 600) {
          return Scaffold(
            appBar: AppBar(title: Text(_destinations[selected].label)),
            body: content,
            bottomNavigationBar: NavigationBar(
              key: const Key('compact-navigation-bar'),
              selectedIndex: selected,
              onDestinationSelected: _selectDestination,
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                    tooltip: destination.label,
                  ),
              ],
            ),
          );
        }

        final expanded = width >= 840;
        return Scaffold(
          appBar: AppBar(title: Text(_destinations[selected].label)),
          body: SafeArea(
            top: false,
            child: Row(
              children: [
                NavigationRail(
                  key: Key(
                    expanded
                        ? 'expanded-navigation-rail'
                        : 'medium-navigation-rail',
                  ),
                  extended: expanded,
                  selectedIndex: selected,
                  onDestinationSelected: _selectDestination,
                  labelType: expanded
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.selected,
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Tooltip(
                          message: destination.label,
                          child: Icon(destination.icon),
                        ),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
