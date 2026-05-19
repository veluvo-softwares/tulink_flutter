import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Bottom card showing journey progress with distance, ETA, participants
/// Matches the design from Image #2 with location, stats, and end button
class JourneyProgressCard extends StatelessWidget {
  const JourneyProgressCard({
    super.key,
    required this.journey,
    required this.convoySnapshot,
    required this.currentUserId,
    required this.isLeader,
    this.onEndJourney,
  });

  final Journey journey;
  final ConvoySnapshot? convoySnapshot;
  final String currentUserId;
  final bool isLeader;
  final VoidCallback? onEndJourney;

  /// Whether the current user is one of the members marked ARRIVED.
  bool get _currentUserArrived {
    final member = convoySnapshot?.members[currentUserId];
    return member?.hasArrived ?? false;
  }

  /// Total participant count used for arrival progress. Falls back to the
  /// snapshot's member map only when there's no event-driven count yet.
  int get _totalCount =>
      convoySnapshot?.totalMembers ?? 1;

  int get _arrivedCount =>
      convoySnapshot?.arrivedMembers.length ?? 0;

  bool get _anyArrived => _arrivedCount > 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(colors),
            const SizedBox(height: 16),
            _buildStats(colors),
            const SizedBox(height: 16),
            _buildParticipants(colors),
            if (_shouldShowWaitingBanner) ...[
              const SizedBox(height: 12),
              _buildWaitingBanner(colors),
            ] else if (convoySnapshot != null && convoySnapshot!.laggingMembers.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStatusMessage(colors),
            ],
            if (_shouldShowActionButton) ...[
              const SizedBox(height: 20),
              _buildEndJourneyButton(colors),
            ],
          ],
        ),
      ),
    );
  }

  /// Build header with destination name
  Widget _buildHeader(TulinkColors colors) {
    return Text(
      journey.destinationAddress,
      style: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: colors.white,
      ),
    );
  }

  /// Build distance and ETA stats
  Widget _buildStats(TulinkColors colors) {
    final distance = _calculateDistance();
    final eta = _calculateETA();
    
    return Row(
      children: [
        Icon(
          Icons.location_on,
          color: colors.electricRed,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          '${distance.toStringAsFixed(1)} km',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.white,
          ),
        ),
        const SizedBox(width: 16),
        Icon(
          Icons.access_time,
          color: colors.silver,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          '${eta.toStringAsFixed(0)} min ETA',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.white,
          ),
        ),
        const Spacer(),
        _buildProgressBadge(colors),
      ],
    );
  }

  /// Right-side badge: shows arrival progress in amber/green once any member
  /// has arrived, falls back to active-member ratio otherwise.
  Widget _buildProgressBadge(TulinkColors colors) {
    final showArrival = _anyArrived;
    final allArrived = convoySnapshot?.allMembersArrived ?? false;

    final bg = showArrival
        ? (allArrived ? Colors.green : Colors.amber).withOpacity(0.18)
        : colors.brushedSteel.withOpacity(0.3);
    final border = showArrival
        ? (allArrived ? Colors.green : Colors.amber).withOpacity(0.45)
        : Colors.transparent;
    final textColor = showArrival
        ? (allArrived ? Colors.green : Colors.amber)
        : colors.white;

    final label = showArrival
        ? '$_arrivedCount/$_totalCount arrived'
        : '${convoySnapshot?.activeMemberCount ?? 1}/$_totalCount';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  /// Build journey participants with avatars
  Widget _buildParticipants(TulinkColors colors) {
    if (convoySnapshot == null || convoySnapshot!.members.isEmpty) {
      return _buildSoloJourneyIndicator(colors);
    }

    final members = convoySnapshot!.members.values.take(5).toList();
    
    return Row(
      children: [
        ...members.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          return Padding(
            padding: EdgeInsets.only(left: index * 8.0),
            child: _buildMemberAvatar(member, index, colors),
          );
        }).toList(),
        if (convoySnapshot!.members.length > 5)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: _buildMoreMembersIndicator(colors),
          ),
      ],
    );
  }

  /// Build member avatar circle. Arrived members get a green checkmark
  /// overlay on the bottom-right; everyone else uses the existing initial.
  Widget _buildMemberAvatar(MemberPosition member, int index, TulinkColors colors) {
    final initials = _getMemberInitials(member.userId);
    final avatarColors = [
      const Color(0xFFE53E3E), // Red
      const Color(0xFF3182CE), // Blue
      const Color(0xFF38A169), // Green
      const Color(0xFFDD6B20), // Orange
      const Color(0xFF805AD5), // Purple
    ];

    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: avatarColors[index % avatarColors.length],
              shape: BoxShape.circle,
              border: Border.all(color: colors.carbonBlack, width: 2),
            ),
            child: Center(
              child: Text(
                initials,
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (member.hasArrived)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.carbonBlack, width: 1.5),
                ),
                child: const Icon(
                  Icons.check,
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build indicator for solo journey
  Widget _buildSoloJourneyIndicator(TulinkColors colors) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF3182CE),
        shape: BoxShape.circle,
        border: Border.all(color: colors.carbonBlack, width: 2),
      ),
      child: Center(
        child: Text(
          'ME',
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Build +N indicator for additional members
  Widget _buildMoreMembersIndicator(TulinkColors colors) {
    final extraCount = convoySnapshot!.members.length - 5;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.brushedSteel,
        shape: BoxShape.circle,
        border: Border.all(color: colors.carbonBlack, width: 2),
      ),
      child: Center(
        child: Text(
          '+$extraCount',
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Build status message for lagging members
  Widget _buildStatusMessage(TulinkColors colors) {
    final laggingMember = convoySnapshot!.laggingMembers.first;
    final distance = _getDistanceBehind(laggingMember);
    final initials = _getMemberInitials(laggingMember.userId);
    
    return Text(
      '$initials is ${distance.toStringAsFixed(1)}km behind',
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.silver,
      ),
    );
  }

  /// Subtle banner shown when the current user has arrived but others are
  /// still en route. Hidden for solo journeys per spec.
  bool get _shouldShowWaitingBanner {
    if (_totalCount <= 1) return false;
    if (!_currentUserArrived) return false;
    return _arrivedCount < _totalCount;
  }

  /// Action button visibility: leaders always see it (END JOURNEY).
  /// Followers see it only after they've arrived (LEAVE JOURNEY). Followers
  /// still en route get no button — they can't end the journey for others
  /// and there's no useful action to expose.
  bool get _shouldShowActionButton => isLeader || _currentUserArrived;

  String get _actionButtonLabel =>
      isLeader ? 'END JOURNEY' : 'LEAVE JOURNEY';

  Widget _buildWaitingBanner(TulinkColors colors) {
    final remaining = _totalCount - _arrivedCount;
    return Text(
      "You've arrived — waiting for $remaining more",
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.silver,
      ),
    );
  }

  /// Build red end-journey / leave-journey button
  Widget _buildEndJourneyButton(TulinkColors colors) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onEndJourney,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.electricRed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          _actionButtonLabel,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  /// Calculate distance to destination
  double _calculateDistance() {
    if (convoySnapshot == null || convoySnapshot!.members.isEmpty) {
      // For solo journey, estimate distance (would come from route calculation)
      return 25.0; // Default estimated distance
    }
    
    // Calculate average distance of convoy members to destination
    double totalDistance = 0.0;
    int memberCount = 0;
    
    for (final member in convoySnapshot!.members.values) {
      final distance = _calculateDistanceBetweenPoints(
        member.latitude,
        member.longitude,
        convoySnapshot!.destination.latitude,
        convoySnapshot!.destination.longitude,
      );
      totalDistance += distance;
      memberCount++;
    }
    
    return memberCount > 0 ? totalDistance / memberCount : 0.0;
  }

  /// Calculate ETA in minutes
  double _calculateETA() {
    if (convoySnapshot == null || convoySnapshot!.members.isEmpty) {
      // For solo journey, estimate based on distance and average speed
      final distance = _calculateDistance();
      const avgSpeed = 50.0; // km/h average city speed
      return (distance / avgSpeed) * 60; // Convert to minutes
    }
    
    // Calculate based on current convoy speed
    final distance = _calculateDistance();
    // Note: averageSpeed doesn't exist, using estimated speed
    const avgSpeed = 50.0;
    
    return (distance / avgSpeed) * 60; // Convert to minutes
  }

  /// Calculate distance in kilometres between two coordinates using the
  /// Haversine formula. Returns kilometres for direct display in the HUD.
  double _calculateDistanceBetweenPoints(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    final double dLat = (lat2 - lat1) * math.pi / 180.0;
    final double dLon = (lon2 - lon1) * math.pi / 180.0;
    final double lat1Rad = lat1 * math.pi / 180.0;
    final double lat2Rad = lat2 * math.pi / 180.0;

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  /// Get distance a member is behind the convoy leader
  double _getDistanceBehind(MemberPosition member) {
    if (convoySnapshot == null || convoySnapshot!.members.isEmpty) return 0.0;
    
    final destination = convoySnapshot!.destination;
    final memberDistance = _calculateDistanceBetweenPoints(
      member.latitude,
      member.longitude,
      destination.latitude,
      destination.longitude,
    );
    
    // Find the closest member to destination
    double minDistance = double.infinity;
    for (final otherMember in convoySnapshot!.members.values) {
      if (otherMember.userId == member.userId) continue;
      
      final distance = _calculateDistanceBetweenPoints(
        otherMember.latitude,
        otherMember.longitude,
        destination.latitude,
        destination.longitude,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    
    return (memberDistance - minDistance).abs();
  }

  /// Get member initials from user ID (simplified)
  String _getMemberInitials(String userId) {
    // In real implementation, this would fetch user name from user service
    // For now, generate initials from user ID
    if (userId.length >= 2) {
      return userId.substring(0, 2).toUpperCase();
    }
    return userId.substring(0, 1).toUpperCase();
  }
}