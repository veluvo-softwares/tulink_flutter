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
    this.onEndJourney,
  });

  final Journey journey;
  final ConvoySnapshot? convoySnapshot;
  final VoidCallback? onEndJourney;

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
            if (convoySnapshot != null && convoySnapshot!.laggingMembers.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStatusMessage(colors),
            ],
            const SizedBox(height: 20),
            _buildEndJourneyButton(colors),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.brushedSteel.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${convoySnapshot?.activeMemberCount ?? 1}/${convoySnapshot?.totalMembers ?? 1}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.white,
            ),
          ),
        ),
      ],
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

  /// Build member avatar circle
  Widget _buildMemberAvatar(MemberPosition member, int index, TulinkColors colors) {
    final initials = _getMemberInitials(member.userId);
    final avatarColors = [
      const Color(0xFFE53E3E), // Red
      const Color(0xFF3182CE), // Blue  
      const Color(0xFF38A169), // Green
      const Color(0xFFDD6B20), // Orange
      const Color(0xFF805AD5), // Purple
    ];
    
    return Container(
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

  /// Build red end journey button
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
          'END JOURNEY',
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

  /// Calculate distance between two points using Haversine formula
  double _calculateDistanceBetweenPoints(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371.0; // Earth radius in kilometers
    
    final double lat1Rad = lat1 * (3.14159 / 180);
    final double lat2Rad = lat2 * (3.14159 / 180);
    final double deltaLatRad = (lat2 - lat1) * (3.14159 / 180);
    final double deltaLonRad = (lon2 - lon1) * (3.14159 / 180);
    
    final double a = (deltaLatRad / 2).abs() * (deltaLatRad / 2).abs() +
        lat1Rad.abs() * lat2Rad.abs() *
        (deltaLonRad / 2).abs() * (deltaLonRad / 2).abs();
    final double c = 2 * (a.abs()).abs();
    
    return earthRadius * c;
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