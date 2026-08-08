import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DirectAiAppShell extends StatelessWidget {
  const DirectAiAppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    _DirectDestination(
      label: 'Trang chủ',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    _DirectDestination(
      label: 'Phân tích',
      icon: Icons.image_search_outlined,
      selectedIcon: Icons.image_search,
    ),
    _DirectDestination(
      label: 'So sánh',
      icon: Icons.compare_arrows_outlined,
      selectedIcon: Icons.compare_arrows,
    ),
    _DirectDestination(
      label: 'Giới thiệu',
      icon: Icons.info_outline,
      selectedIcon: Icons.info,
    ),
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
        if (constraints.maxWidth < 600) {
          return Scaffold(
            appBar: AppBar(title: Text(_destinations[selected].label)),
            body: content,
            bottomNavigationBar: NavigationBar(
              key: const Key('direct-compact-navigation-bar'),
              selectedIndex: selected,
              onDestinationSelected: _selectDestination,
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(
                      destination.icon,
                      semanticLabel: destination.label,
                    ),
                    selectedIcon: Icon(
                      destination.selectedIcon,
                      semanticLabel: destination.label,
                    ),
                    label: destination.label,
                    tooltip: destination.label,
                  ),
              ],
            ),
          );
        }

        final expanded = constraints.maxWidth >= 840;
        return Scaffold(
          appBar: AppBar(title: Text(_destinations[selected].label)),
          body: SafeArea(
            top: false,
            child: Row(
              children: [
                NavigationRail(
                  key: Key(
                    expanded
                        ? 'direct-expanded-navigation-rail'
                        : 'direct-medium-navigation-rail',
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
                          child: Icon(
                            destination.icon,
                            semanticLabel: destination.label,
                          ),
                        ),
                        selectedIcon: Icon(
                          destination.selectedIcon,
                          semanticLabel: destination.label,
                        ),
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

class _DirectDestination {
  const _DirectDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
