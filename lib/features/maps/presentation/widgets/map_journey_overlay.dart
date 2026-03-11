import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class MapJourneyOverlay extends StatelessWidget {
  const MapJourneyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: colors.brushedSteel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Journey Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat(context, "DISTANCE", "12.4", "KM"),
                _buildStat(context, "TIME", "00:45", "MIN"),
                _buildStat(context, "PACE", "5:20", "/KM"),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.electricRed,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text("RESUME JOURNEY"),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: colors.brushedSteel,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.stop_rounded, color: colors.electricRed, size: 28),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value, String unit) {
    final colors = Theme.of(context).tulinkColors;
    
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.silver,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 4)),
              TextSpan(
                text: unit,
                style: TextStyle(
                  color: colors.silver,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}