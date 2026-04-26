import 'package:equatable/equatable.dart';

import 'member_position.dart';

/// Represents a complete convoy snapshot with all member positions and destination
/// This is the main domain entity for convoy coordination state
class ConvoySnapshot extends Equatable {
  const ConvoySnapshot({
    required this.journeyId,
    required this.members,
    required this.destination,
    required this.destinationAddress,
    this.timestamp,
  });

  /// The journey ID this convoy belongs to
  final String journeyId;

  /// Map of user ID to their current position
  final Map<String, MemberPosition> members;

  /// Destination coordinates
  final ConvoyDestination destination;

  /// Human-readable destination address
  final String destinationAddress;

  /// When this snapshot was created
  final DateTime? timestamp;

  /// Get list of all members sorted by their last update time
  List<MemberPosition> get membersList {
    final list = members.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Most recent first
    return list;
  }

  /// Get list of active members (not stale)
  List<MemberPosition> get activeMembers {
    return membersList.where((member) => !member.isStale).toList();
  }

  /// Get list of stale members (no updates in 30+ seconds)
  List<MemberPosition> get staleMembers {
    return membersList.where((member) => member.isStale).toList();
  }

  /// Get list of moving members
  List<MemberPosition> get movingMembers {
    return activeMembers.where((member) => member.isMoving && (member.speed ?? 0) > 0.5).toList();
  }

  /// Get list of members with low battery
  List<MemberPosition> get lowBatteryMembers {
    return activeMembers.where((member) => member.hasLowBattery).toList();
  }

  /// Get list of lagging members
  List<MemberPosition> get laggingMembers {
    return activeMembers.where((member) => member.isLagging).toList();
  }

  /// Get list of arrived members
  List<MemberPosition> get arrivedMembers {
    return membersList.where((member) => member.hasArrived).toList();
  }

  /// Total number of convoy members
  int get totalMembers => members.length;

  /// Number of active convoy members
  int get activeMemberCount => activeMembers.length;

  /// Number of moving members
  int get movingMemberCount => movingMembers.length;

  /// Check if convoy has any active members
  bool get hasActiveMembers => activeMembers.isNotEmpty;

  /// Check if all members have arrived
  bool get allMembersArrived => totalMembers > 0 && arrivedMembers.length == totalMembers;

  /// Get convoy status summary
  String get statusSummary {
    if (allMembersArrived) return 'ALL ARRIVED';
    if (!hasActiveMembers) return 'NO ACTIVE MEMBERS';
    if (laggingMembers.isNotEmpty) return 'MEMBERS LAGGING';
    if (movingMemberCount > 0) return 'IN PROGRESS';
    return 'STOPPED';
  }

  /// Update a member's position in the snapshot
  ConvoySnapshot updateMember(MemberPosition position) {
    final updatedMembers = Map<String, MemberPosition>.from(members);
    updatedMembers[position.userId] = position;
    
    return copyWith(
      members: updatedMembers,
      timestamp: DateTime.now(),
    );
  }

  /// Remove a member from the convoy
  ConvoySnapshot removeMember(String userId) {
    final updatedMembers = Map<String, MemberPosition>.from(members);
    updatedMembers.remove(userId);
    
    return copyWith(
      members: updatedMembers,
      timestamp: DateTime.now(),
    );
  }

  /// Add multiple members to the convoy
  ConvoySnapshot updateMembers(List<MemberPosition> newPositions) {
    final updatedMembers = Map<String, MemberPosition>.from(members);
    
    for (final position in newPositions) {
      updatedMembers[position.userId] = position;
    }
    
    return copyWith(
      members: updatedMembers,
      timestamp: DateTime.now(),
    );
  }

  /// Filter out a specific user from the members (e.g., current user)
  ConvoySnapshot filterOutUser(String userId) {
    final filteredMembers = Map<String, MemberPosition>.from(members);
    filteredMembers.remove(userId);
    
    return copyWith(members: filteredMembers);
  }

  /// Copy with new values
  ConvoySnapshot copyWith({
    String? journeyId,
    Map<String, MemberPosition>? members,
    ConvoyDestination? destination,
    String? destinationAddress,
    DateTime? timestamp,
  }) {
    return ConvoySnapshot(
      journeyId: journeyId ?? this.journeyId,
      members: members ?? this.members,
      destination: destination ?? this.destination,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  List<Object?> get props => [
        journeyId,
        members,
        destination,
        destinationAddress,
        timestamp,
      ];

  @override
  String toString() {
    return 'ConvoySnapshot('
        'journeyId: $journeyId, '
        'members: ${members.length}, '
        'active: $activeMemberCount, '
        'status: $statusSummary'
        ')';
  }
}

/// Represents the convoy destination coordinates
class ConvoyDestination extends Equatable {
  const ConvoyDestination({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  List<Object> get props => [latitude, longitude];

  @override
  String toString() {
    return 'ConvoyDestination(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)})';
  }
}

/// Connection state for real-time convoy coordination
enum ConvoyConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}