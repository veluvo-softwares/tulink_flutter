import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

/// A reusable card widget for displaying journey information
class JourneyInfoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const JourneyInfoCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider),
      ),
      child: child,
    );
  }
}

/// Content wrapper for journey info cards with icon, title, and subtitle
class JourneyInfoCardContent extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;

  const JourneyInfoCardContent({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Row(
      children: [
        icon,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Grid layout for displaying multiple journey info items
class JourneyInfoCardGrid extends StatelessWidget {
  final List<JourneyInfoCardItem> items;
  final int crossAxisCount;

  const JourneyInfoCardGrid({
    super.key,
    required this.items,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _JourneyInfoGridItem(item: items[index]);
      },
    );
  }
}

/// Individual item for the journey info grid
class JourneyInfoCardItem {
  final String title;
  final String value;
  final IconData icon;
  final Color? iconColor;

  const JourneyInfoCardItem({
    required this.title,
    required this.value,
    required this.icon,
    this.iconColor,
  });
}

/// Grid item widget for displaying journey info
class _JourneyInfoGridItem extends StatelessWidget {
  final JourneyInfoCardItem item;

  const _JourneyInfoGridItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warmSand,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: item.iconColor ?? colors.routeTeal, size: 20),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: TextStyle(
              color: colors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: TextStyle(
              color: colors.ink,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
