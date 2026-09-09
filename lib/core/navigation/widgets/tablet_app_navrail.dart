import 'package:flutter/material.dart';

import '../../theme/tulink_colors.dart';

class TabletAppNavRail extends StatelessWidget {
  const TabletAppNavRail({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.invitationCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int invitationCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Material(
      color: colors.surface.withValues(alpha: .97),
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NavItem(
              label: 'Map',
              icon: Icons.map_outlined,
              selectedIcon: Icons.map_rounded,
              selected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              label: 'Journeys',
              icon: Icons.route_outlined,
              selectedIcon: Icons.route_rounded,
              selected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            _NavItem(
              label: 'Invites',
              icon: Icons.mail_outline_rounded,
              selectedIcon: Icons.mail_rounded,
              selected: currentIndex == 2,
              badge: invitationCount,
              onTap: () => onTap(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 76,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? colors.routeTeal : colors.muted,
                  size: 25,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.deepTeal : colors.muted,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
