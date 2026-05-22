import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class SettingsMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? titleColor;
  final Color? iconColor;
  final bool showArrow;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SettingsMenuItem({
    super.key,
    required this.icon,
    required this.title,
    this.titleColor,
    this.iconColor,
    this.showArrow = true,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: iconColor ?? colors.white,
                  size: 20,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Title
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: titleColor ?? colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              // Trailing widget or arrow
              if (trailing != null)
                trailing!
              else if (showArrow)
                Icon(
                  Icons.arrow_forward_ios,
                  color: colors.silver.withOpacity(0.6),
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }
}