import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class ProfileStatsGrid extends StatelessWidget {
  final int journeyCount;
  final double totalDistance;
  final int leaderboardPosition;

  const ProfileStatsGrid({
    super.key,
    required this.journeyCount,
    required this.totalDistance,
    required this.leaderboardPosition,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            context,
            label: 'JOURNEYS',
            value: journeyCount.toString(),
            colors: colors,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatItem(
            context,
            label: 'DISTANCE',
            value: _formatDistance(totalDistance),
            unit: 'KM',
            colors: colors,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatItem(
            context,
            label: 'LED',
            value: leaderboardPosition.toString(),
            colors: colors,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    String? unit,
    required TulinkColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Label
          Text(
            label,
            style: TextStyle(
              color: colors.silver,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Value
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                if (unit != null)
                  TextSpan(
                    text: '\n$unit',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double distance) {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}k';
    } else if (distance >= 10) {
      return distance.toStringAsFixed(0);
    } else {
      return distance.toStringAsFixed(1);
    }
  }
}