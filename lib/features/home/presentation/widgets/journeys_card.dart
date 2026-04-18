import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../journeys/domain/entities/journey.dart';

/// A reusable card widget that displays up to 4 journeys in a single container
/// Can be used for both recent journeys and active journeys
class JourneysCard extends StatelessWidget {
  final List<Journey> journeys;
  final String title;
  final VoidCallback? onSeeAll;
  final void Function(Journey)? onJourneyTap;
  final bool showParticipants;

  const JourneysCard({
    super.key,
    required this.journeys,
    required this.title,
    this.onSeeAll,
    this.onJourneyTap,
    this.showParticipants = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final displayJourneys = journeys.take(4).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.brushedSteel.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and "See all" button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: colors.electricRed,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Journey items
          if (displayJourneys.isEmpty)
            _buildEmptyState(colors)
          else
            ...displayJourneys.asMap().entries.map((entry) {
              final index = entry.key;
              final journey = entry.value;
              final isLast = index == displayJourneys.length - 1;
              
              return Column(
                children: [
                  _buildJourneyItem(journey, colors),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        color: colors.brushedSteel.withOpacity(0.3),
                        height: 1,
                      ),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildJourneyItem(Journey journey, TulinkColors colors) {
    return GestureDetector(
      onTap: () => onJourneyTap?.call(journey),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Journey icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.electricRed.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.electricRed.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.route,
                color: colors.electricRed,
                size: 20,
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Journey details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Journey name
                  Text(
                    journey.name,
                    style: TextStyle(
                      color: colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Destination and time or participants
                  Text(
                    showParticipants 
                        ? '${journey.participants?.length ?? 0} participants • ${journey.destinationAddress}'
                        : '${_formatDate(journey.createdAt)} • ${journey.destinationAddress}',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Status indicator
            StatusIndicator(status: journey.status),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(TulinkColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.route_outlined,
            color: colors.silver,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            showParticipants ? 'No active journeys' : 'No recent journeys',
            style: TextStyle(
              color: colors.silver,
              fontSize: 14,
            ),
          ),
          if (showParticipants)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Start a journey to see it here',
                style: TextStyle(
                  color: colors.silver.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return 'Recently';
    }
  }
}