import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';

class AppNavbar extends StatelessWidget {
  const AppNavbar({
    super.key,
    required this.currentIndex,
    required this.invitationCount,
    required this.onTap,
  });

  final int currentIndex;
  final int invitationCount;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return NavigationBar(
      height: 72,
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: colors.surface,
      indicatorColor: colors.routeTeal.withValues(alpha: .14),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map_rounded),
          label: 'Map',
        ),
        const NavigationDestination(
          icon: Icon(Icons.route_outlined),
          selectedIcon: Icon(Icons.route_rounded),
          label: 'Journeys',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: invitationCount > 0,
            label: Text(invitationCount > 9 ? '9+' : '$invitationCount'),
            child: const Icon(Icons.mail_outline_rounded),
          ),
          selectedIcon: Badge(
            isLabelVisible: invitationCount > 0,
            label: Text(invitationCount > 9 ? '9+' : '$invitationCount'),
            child: const Icon(Icons.mail_rounded),
          ),
          label: 'Invites',
        ),
      ],
    );
  }
}
