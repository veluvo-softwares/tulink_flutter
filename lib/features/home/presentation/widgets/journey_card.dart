import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/theme/tulink_colors.dart';

class JourneyCard extends StatelessWidget {
  final String title;
  final String description;
  final List<Color>? colors;
  final Color? borderColor;
 
  final VoidCallback? onTap;
  final String? iconText;

  const JourneyCard({
    super.key,
    required this.title,
    required this.description,
    this.colors,
    this.borderColor,
    this.onTap,
    this.iconText
  }) : assert(colors != null || borderColor != null, 'Either colors or borderColor must be provided');

  @override
  Widget build(BuildContext context) {
    final themeColors = Theme.of(context).tulinkColors;
   
    final bool hasBorder = borderColor != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: hasBorder ? themeColors.carbonBlack : null,
          gradient: hasBorder ? null : LinearGradient(
            colors: colors!,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: hasBorder ? Border.all(color: borderColor!, width: 2) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (hasBorder ? borderColor! : colors!.first).withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (iconText != null) ...[
              const SizedBox(width: 12),
              Container(
                alignment: Alignment.center,
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: themeColors.carbonBlack,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  iconText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}