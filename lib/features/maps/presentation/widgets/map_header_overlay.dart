import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';
import 'package:google_fonts/google_fonts.dart';

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
              color: colors.brushedSteel.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.white, size: 20),
            ),
          ),
          
          // Race Title Info
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "RIO MARATHON 2024",
                style: GoogleFonts.rajdhani(
                  color: colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.electricRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.electricRed.withValues(alpha: 0.5), width: 1),
                ),
                child: Text(
                  "ACTIVE JOURNEY",
                  style: TextStyle(
                    color: colors.electricRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          
          // Settings / Profile Icon
          Container(
            decoration: BoxDecoration(
              color: colors.brushedSteel.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () {},
              icon: Icon(Icons.tune_rounded, color: colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
