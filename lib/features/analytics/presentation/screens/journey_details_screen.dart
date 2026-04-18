import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../journeys/presentation/widgets/journey_preview_map.dart';

class JourneyDetailsScreen extends StatelessWidget {
  final Journey journey;

  const JourneyDetailsScreen({
    super.key,
    required this.journey,
  });

  static const String routeName = '/journey-details';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // App Bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    Text(
                      'Journey Details',
                      style: TextStyle(
                        color: colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),
            ),

            // Compact Map View
            Container(
              height: 180,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.brushedSteel.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: JourneyPreviewMap(journey: journey),
              ),
            ),

            const SizedBox(height: 20),

            // Journey Title and Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      journey.name,
                      style: TextStyle(
                        color: colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  StatusIndicator(
                    status: journey.status,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'CONVOY • ',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    journey.createdAt != null 
                        ? 'CREATED ${_getTimeAgo(journey.createdAt)}'
                        : 'CREATED RECENTLY',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Destination Card (without edit button)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.brushedSteel.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: colors.electricRed,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DESTINATION',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          journey.destinationAddress,
                          style: TextStyle(
                            color: colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Journey Info Cards Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      colors,
                      'TYPE',
                      'Convoy',
                      Icons.route,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoCard(
                      colors,
                      'LAG LIMIT',
                      '${journey.lagThresholdMeters}m',
                      Icons.speed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoCard(
                      colors,
                      'DRIVERS',
                      '${journey.participants?.length ?? 1}',
                      Icons.group,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(TulinkColors colors, String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.brushedSteel.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.electricRed, size: 20),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: colors.silver,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  String _getTimeAgo(DateTime? date) {
    if (date == null) return 'UNKNOWN TIME';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}MO AGO';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}D AGO';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}H AGO';
    } else {
      return 'RECENTLY';
    }
  }
}