import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class MapHeaderOverlay extends StatelessWidget {
  const MapHeaderOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(
        top: topPadding + 8,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.black.withValues(alpha: 0.4),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back Button / Menu
          Container(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back',
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: colors.ink,
                size: 20,
              ),
            ),
          ),

          // Race Title Info
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tulink map',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.routeTeal.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: colors.routeTeal.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  'MAP VIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
