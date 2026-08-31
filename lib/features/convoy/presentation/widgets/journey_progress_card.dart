import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../maps/domain/entities/last_known_progress.dart';
import '../../../maps/domain/entities/route_progress.dart';
import '../utils/convoy_member_presentation.dart';

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
    this.onLeaveJourney,
    this.routeProgress,
    this.lastKnownProgress,
    this.isActionInProgress = false,
    this.isExpanded = false,
    this.onToggleExpanded,
    this.onMemberTap,
  });

  final Journey journey;
  final ConvoySnapshot? convoySnapshot;
  final String currentUserId;
  final bool isLeader;
  final VoidCallback? onEndJourney;
  final VoidCallback? onLeaveJourney;
  final RouteProgress? routeProgress;

  /// Figures recovered from disk, shown while [routeProgress] is still null so
  /// a resumed journey reads its real distance and ETA instead of placeholders.
  final LastKnownProgress? lastKnownProgress;

  final bool isActionInProgress;

  /// When false the card renders as a compact pill to keep the map visible.
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;

  /// Focuses the selected member directly on the map. Member identifiers are
  /// never exposed in an intermediate sheet.
  final ValueChanged<MemberPosition>? onMemberTap;

  /// Whether the current user is one of the members marked ARRIVED.
  bool get _currentUserArrived {
    final member = convoySnapshot?.members[currentUserId];
    return member?.hasArrived ?? false;
  }

  /// Total participant count used for arrival progress. Falls back to the
  /// snapshot's member map only when there's no event-driven count yet.
  int get _totalCount => convoySnapshot?.totalMembers ?? 1;

  int get _arrivedCount => convoySnapshot?.arrivedMembers.length ?? 0;

  bool get _anyArrived => _arrivedCount > 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    return isExpanded ? _buildExpanded(colors) : _buildCollapsedPill(colors);
  }

  /// Compact single-row pill — keeps the map largely unobstructed while
  /// driving.  Tapping it expands to the full card.
  Widget _buildCollapsedPill(TulinkColors colors) {
    return GestureDetector(
      onTap: onToggleExpanded,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.location_on, color: colors.sunsetOrange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  journey.destinationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildProgressBadge(colors),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_up, color: colors.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Full expanded card — stats, participants, action button.
  Widget _buildExpanded(TulinkColors colors) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
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
            ] else if (convoySnapshot != null &&
                convoySnapshot!.laggingMembers.isNotEmpty) ...[
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

  /// Build header with destination name and collapse chevron.
  Widget _buildHeader(TulinkColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            journey.destinationLabel,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
        ),
        GestureDetector(
          onTap: onToggleExpanded,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.keyboard_arrow_down,
              color: colors.muted,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  /// Build distance and ETA stats.
  ///
  /// Prefers live progress, falls back to the snapshot restored from disk, and
  /// only shows placeholders when neither exists. A restored snapshot older
  /// than [LastKnownProgress.freshFor] is dimmed and labelled with its age —
  /// the beacon writes every few seconds, so anything newer is effectively
  /// live and flagging it would be noise on every resume.
  Widget _buildStats(TulinkColors colors) {
    final restored = routeProgress == null ? lastKnownProgress : null;
    final hasRouteProgress = routeProgress != null;
    final hasFigures = hasRouteProgress || restored != null;

    final distance = hasRouteProgress
        ? _calculateDistance()
        : (restored?.distanceRemainingMetres ?? 0) / 1000;
    final eta = hasRouteProgress
        ? _calculateETA()
        : (restored?.durationRemainingSeconds ?? 0) / 60;

    final isStale = restored?.isStaleAt(DateTime.now()) ?? false;
    final figureColor = isStale ? colors.muted : colors.ink;

    return Row(
      children: [
        Icon(Icons.location_on, color: colors.sunsetOrange, size: 16),
        const SizedBox(width: 4),
        Text(
          hasFigures ? '${distance.toStringAsFixed(1)} km' : '-- km',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: figureColor,
          ),
        ),
        const SizedBox(width: 16),
        Icon(Icons.access_time, color: colors.muted, size: 16),
        const SizedBox(width: 4),
        Text(
          hasFigures ? '${eta.ceil()} min ETA' : 'Calculating ETA',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: figureColor,
          ),
        ),
        if (isStale && restored != null) ...[
          const SizedBox(width: 6),
          Text(
            _ageLabel(restored.ageAt(DateTime.now())),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: colors.muted,
            ),
          ),
        ],
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
        : colors.warmSand;
    final border = showArrival
        ? (allArrived ? Colors.green : Colors.amber).withOpacity(0.45)
        : Colors.transparent;
    final textColor = showArrival
        ? (allArrived ? Colors.green : Colors.amber)
        : colors.ink;

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
        style: TextStyle(
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

    final identities = _identities;
    final members = convoySnapshot!.members.values.toList()
      ..sort((a, b) {
        final aIndex = identities.keys.toList().indexOf(a.userId);
        final bIndex = identities.keys.toList().indexOf(b.userId);
        return aIndex.compareTo(bIndex);
      });

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
  Widget _buildMemberAvatar(
    MemberPosition member,
    int index,
    TulinkColors colors,
  ) {
    final identity = _identities[member.userId];
    final initials =
        identity?.initials ??
        ConvoyMemberPresentation.initialsFor(member.userId);

    return Semantics(
      label: 'Show ${identity?.displayName ?? 'convoy member'} on map',
      button: onMemberTap != null,
      child: GestureDetector(
        key: ValueKey('convoy-member-${member.userId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onMemberTap == null ? null : () => onMemberTap!(member),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      identity?.color ??
                      ConvoyMemberPresentation.palette[index %
                          ConvoyMemberPresentation.palette.length],
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
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
                      border: Border.all(color: colors.surface, width: 1.5),
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
        border: Border.all(color: colors.surface, width: 2),
      ),
      child: Center(
        child: Text(
          'ME',
          style: TextStyle(
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
        color: colors.muted,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 2),
      ),
      child: Center(
        child: Text(
          '+$extraCount',
          style: TextStyle(
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
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.muted,
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

  /// Leaders end the convoy for everyone; followers may leave at any point.
  bool get _shouldShowActionButton => true;

  String get _actionButtonLabel => isLeader ? 'END JOURNEY' : 'LEAVE JOURNEY';

  Widget _buildWaitingBanner(TulinkColors colors) {
    final remaining = _totalCount - _arrivedCount;
    return Text(
      "You've arrived — waiting for $remaining more",
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.muted,
      ),
    );
  }

  /// Build red end-journey / leave-journey button
  Widget _buildEndJourneyButton(TulinkColors colors) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: isActionInProgress
            ? null
            : (isLeader ? onEndJourney : onLeaveJourney),
        style: ElevatedButton.styleFrom(
          backgroundColor: isLeader ? colors.sunsetOrange : colors.deepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isActionInProgress
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                _actionButtonLabel,
                style: TextStyle(
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
  /// Short age for a stale snapshot, e.g. "2 min ago".
  static String _ageLabel(Duration age) {
    if (age.inMinutes < 1) return '${age.inSeconds} sec ago';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    final hours = age.inHours;
    return '$hours hr${hours == 1 ? '' : 's'} ago';
  }

  double _calculateDistance() {
    if (routeProgress != null) {
      return routeProgress!.distanceRemainingMetres / 1000;
    }
    if (convoySnapshot == null || convoySnapshot!.members.isEmpty) {
      // For solo journey, estimate distance (would come from route calculation)
      return 0;
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
    if (routeProgress != null) {
      return routeProgress!.durationRemainingSeconds / 60;
    }
    if (convoySnapshot == null || convoySnapshot!.members.isEmpty) {
      return 0;
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
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;
    final double dLat = (lat2 - lat1) * math.pi / 180.0;
    final double dLon = (lon2 - lon1) * math.pi / 180.0;
    final double lat1Rad = lat1 * math.pi / 180.0;
    final double lat2Rad = lat2 * math.pi / 180.0;

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
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

  Map<String, ConvoyMemberPresentation> get _identities =>
      ConvoyMemberPresentation.forJourney(
        journey,
        additionalUserIds: convoySnapshot?.members.keys ?? const [],
      );

  /// Get member initials from the journey roster, falling back to user ID.
  String _getMemberInitials(String userId) {
    return _identities[userId]?.initials ??
        ConvoyMemberPresentation.initialsFor(userId);
  }
}
