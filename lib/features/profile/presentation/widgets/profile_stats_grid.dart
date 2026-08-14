import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';

class ProfileStatsGrid extends StatelessWidget {
  const ProfileStatsGrid({
    required this.journeyCount,
    required this.totalDistance,
    required this.leaderboardPosition,
    super.key,
  });

  final int journeyCount;
  final double totalDistance;
  final int leaderboardPosition;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(label: 'Journeys', value: '$journeyCount'),
          ),
          SizedBox(height: 42, child: VerticalDivider(color: colors.divider)),
          Expanded(
            child: _Stat(
              label: 'Distance',
              value: _formatDistance(totalDistance),
              suffix: ' km',
            ),
          ),
          SizedBox(height: 42, child: VerticalDivider(color: colors.divider)),
          Expanded(
            child: _Stat(label: 'Led', value: '$leaderboardPosition'),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double distance) {
    if (distance >= 1000) return '${(distance / 1000).toStringAsFixed(1)}k';
    if (distance >= 10) return distance.toStringAsFixed(0);
    return distance.toStringAsFixed(1);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.suffix});

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Column(
      children: [
        Text(
          '$value${suffix ?? ''}',
          maxLines: 1,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: colors.deepTeal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
