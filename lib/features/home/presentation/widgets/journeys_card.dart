import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../../core/widgets/status_indicator.dart';
import '../../../../core/widgets/shimmer_widgets.dart';
import '../../../journeys/domain/entities/journey.dart';

/// A reusable card widget that displays up to 4 journeys in a single container
/// Can be used for both recent journeys and active journeys
class JourneysCard extends StatelessWidget {
  final List<Journey> journeys;
  final String title;
  final VoidCallback? onSeeAll;
  final void Function(Journey)? onJourneyTap;
  final bool showParticipants;
  final bool isLoading;

  const JourneysCard({
    super.key,
    required this.journeys,
    required this.title,
    this.onSeeAll,
    this.onJourneyTap,
    this.showParticipants = false,
    this.isLoading = false,
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
              if (displayJourneys.isNotEmpty && onSeeAll != null)
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
          
          // Journey items or loading state
          if (isLoading && displayJourneys.isEmpty)
            _buildLoadingState()
          else if (displayJourneys.isEmpty)
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
                journey.isScheduled ? Icons.event : Icons.route,
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

            // Scheduled journeys show the countdown where the status dot
            // would otherwise sit — "PENDING" reads as broken for a journey
            // that intentionally starts tomorrow.
            if (journey.isScheduled)
              _buildCountdownChip(journey.scheduledFor!, colors)
            else
              StatusIndicator(status: journey.status),
          ],
        ),
      ),
    );
  }

  /// Compact "starts in…" chip for scheduled journeys.
  Widget _buildCountdownChip(DateTime scheduledFor, TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.electricRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.electricRed.withOpacity(0.4)),
      ),
      child: Text(
        _formatCountdown(scheduledFor),
        style: TextStyle(
          color: colors.electricRed,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _formatCountdown(DateTime scheduledFor) {
    final remaining = scheduledFor.difference(DateTime.now());
    if (remaining.isNegative) return 'due now';
    if (remaining.inDays >= 1) {
      return 'in ${remaining.inDays}d ${remaining.inHours % 24}h';
    }
    if (remaining.inHours >= 1) {
      return 'in ${remaining.inHours}h ${remaining.inMinutes % 60}m';
    }
    return 'in ${remaining.inMinutes}m';
  }

  Widget _buildEmptyState(TulinkColors colors) {
    return Column(
      children: [
        Icon(
          Icons.route_outlined,
          color: colors.electricRed,
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
      
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: showParticipants ? Text(
              'Start a journey to see it here',
              style: TextStyle(
                color: colors.silver.withOpacity(0.7),
                fontSize: 12,
              ),
            ) : Text(
              'Your recent journeys will show up here',
              style: TextStyle(
                color: colors.silver.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        // Generate 3 shimmer items that match the journey item layout
        ...List.generate(3, (index) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Builder(
                builder: (context) => ShimmerEffect.listItem(context),
              ),
            ),
            if (index < 2)
              Builder(
                builder: (context) {
                  final colors = Theme.of(context).tulinkColors;
                  return Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: colors.brushedSteel.withValues(alpha: 0.3),
                  );
                },
              ),
          ],
        )),
      ],
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