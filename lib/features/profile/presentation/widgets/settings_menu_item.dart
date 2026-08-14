import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';

class SettingsMenuItem extends StatelessWidget {
  const SettingsMenuItem({
    required this.icon,
    required this.title,
    super.key,
    this.titleColor,
    this.iconColor,
    this.subtitle,
    this.showArrow = true,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color? titleColor;
  final Color? iconColor;
  final String? subtitle;
  final bool showArrow;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (iconColor ?? colors.routeTeal).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? colors.deepTeal,
                  size: 20,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor ?? colors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),

              if (trailing != null)
                trailing!
              else if (showArrow)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.muted,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
