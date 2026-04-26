import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Bottom sheet showing convoy metrics: distance, time, pace
/// Matches the design from the target interface
class ConvoyMetricsBottomSheet extends StatefulWidget {
  const ConvoyMetricsBottomSheet({
    super.key,
    required this.snapshot,
    required this.journeyName,
    this.onEndJourney,
  });

  final ConvoySnapshot snapshot;
  final String journeyName;
  final VoidCallback? onEndJourney;

  @override
  State<ConvoyMetricsBottomSheet> createState() => _ConvoyMetricsBottomSheetState();
}

class _ConvoyMetricsBottomSheetState extends State<ConvoyMetricsBottomSheet> 
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup pulsing animation for active indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return Container(
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Journey info header
          _buildJourneyHeader(colors),
          
          // Metrics row
          _buildMetricsRow(colors),
          
          // Active status and action button
          _buildActionSection(colors),
        ],
      ),
    );
  }

  /// Build journey header with status
  Widget _buildJourneyHeader(TulinkColors colors) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Status indicator
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(width: 12),
          
          // Journey status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IN PROGRESS',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.journeyName,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Riders count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.brushedSteel.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.group,
                  size: 14,
                  color: colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.snapshot.totalMembers + 1} riders', // +1 for current user
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build metrics row with distance, time, and pace
  Widget _buildMetricsRow(TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Distance
          Expanded(
            child: _buildMetricItem(
              colors,
              'DISTANCE',
              _getFormattedDistance(),
              'KM',
            ),
          ),
          
          // Divider
          Container(
            width: 1,
            height: 40,
            color: colors.brushedSteel.withOpacity(0.3),
          ),
          
          // Time
          Expanded(
            child: _buildMetricItem(
              colors,
              'TIME',
              _getFormattedTime(),
              'MIN',
            ),
          ),
          
          // Divider
          Container(
            width: 1,
            height: 40,
            color: colors.brushedSteel.withOpacity(0.3),
          ),
          
          // Pace
          Expanded(
            child: _buildMetricItem(
              colors,
              'PACE',
              _getFormattedPace(),
              '/KM',
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual metric item
  Widget _buildMetricItem(TulinkColors colors, String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.silver,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: colors.white,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.silver,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build action section with active status and end journey button
  Widget _buildActionSection(TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Active status
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.brushedSteel.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.brushedSteel.withOpacity(0.3),
                ),
              ),
              child: Text(
                'ACTIVE',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.white,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // End journey button
          SizedBox(
            width: 60,
            height: 44,
            child: ElevatedButton(
              onPressed: widget.onEndJourney,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.electricRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Icon(
                Icons.stop,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Calculate and format journey distance
  String _getFormattedDistance() {
    final totalDistance = widget.snapshot.totalDistance;
    if (totalDistance < 1.0) {
      // Show in meters if less than 1km
      return '${(totalDistance * 1000).toStringAsFixed(0)}m';
    }
    return totalDistance.toStringAsFixed(1);
  }

  /// Calculate and format journey time
  String _getFormattedTime() {
    final duration = widget.snapshot.journeyDuration;
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}';
  }

  /// Calculate and format journey pace
  String _getFormattedPace() {
    final pace = widget.snapshot.averagePace;
    if (pace == 0) return '0:00';
    
    final minutes = pace.floor();
    final seconds = ((pace - minutes) * 60).round();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Extension for convoy metrics calculations
extension ConvoyMetricsCalculations on ConvoySnapshot {
  /// Calculate total convoy distance covered
  /// Uses the average distance of all convoy members
  double get totalDistance {
    if (members.isEmpty) return 0.0;
    
    double totalDistance = 0.0;
    int memberCount = 0;
    
    // Calculate distance for each member from their starting position
    for (final member in members.values) {
      // For now, estimate based on member movement
      // In a real implementation, this would track cumulative distance over time
      if (member.speed != null && member.speed! > 0) {
        // Rough estimation: assume member has been moving at current speed
        final estimatedTime = 5.0; // 5 minutes average
        final estimatedDistance = (member.speed! * estimatedTime * 60) / 1000; // Convert to km
        totalDistance += estimatedDistance;
        memberCount++;
      }
    }
    
    return memberCount > 0 ? totalDistance / memberCount : 0.0;
  }

  /// Calculate convoy duration
  /// Uses journey start time vs current time
  Duration get journeyDuration {
    // Calculate duration based on the oldest member timestamp
    if (members.isEmpty) return const Duration();
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final oldestTimestamp = members.values
        .map((member) => member.timestamp)
        .reduce((a, b) => a < b ? a : b);
    
    final durationMs = now - oldestTimestamp;
    return Duration(milliseconds: durationMs.clamp(0, double.infinity).toInt());
  }

  /// Calculate average convoy pace (minutes per km)
  double get averagePace {
    final distance = totalDistance;
    final duration = journeyDuration;
    
    if (distance == 0 || duration.inSeconds == 0) return 0.0;
    
    return duration.inMinutes / distance; // minutes per km
  }

  /// Get convoy speed in km/h
  double get averageSpeed {
    final distance = totalDistance;
    final duration = journeyDuration;
    
    if (distance == 0 || duration.inSeconds == 0) return 0.0;
    
    return distance / (duration.inHours); // km/h
  }

  /// Check if all convoy members are active
  bool get allMembersActive {
    return members.values.every((member) => !member.isStale);
  }

  /// Get convoy status summary
  String get statusSummary {
    if (allMembersArrived) return 'COMPLETED';
    if (laggingMembers.isNotEmpty) return 'LAGGING';
    if (movingMemberCount > 0) return 'MOVING';
    return 'WAITING';
  }
}

/// Extensions for member position status checks
extension MemberPositionStatus on MemberPosition {
  /// Check if member position is stale (no updates recently)
  bool get isStale {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeDiff = now - timestamp;
    return timeDiff > 30000; // 30 seconds
  }

  /// Check if member is lagging behind
  bool get isLagging {
    return statusChange == 'LAG';
  }

  /// Check if member has arrived
  bool get hasArrived {
    return statusChange == 'ARRIVED';
  }

  /// Check if member has low battery
  bool get hasLowBattery {
    return batteryLevel != null && batteryLevel! < 20;
  }
}