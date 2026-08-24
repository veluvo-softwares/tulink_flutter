import 'package:equatable/equatable.dart';

enum JourneyStatus { PENDING, ACTIVE, PAUSED, COMPLETED, CANCELLED }

enum ParticipantRole { LEADER, FOLLOWER }

enum ParticipantStatus { INVITED, ACTIVE, LEFT }

// Type alias for backward compatibility with analytics screens
typedef JourneyParticipant = Participant;

class LatLng extends Equatable {
  final double latitude;
  final double longitude;

  const LatLng({required this.latitude, required this.longitude});

  @override
  List<Object?> get props => [latitude, longitude];
}

class Journey extends Equatable {
  final String id;
  final String? inviteCode;
  final String name;
  final String leaderId;
  final JourneyStatus status;
  final LatLng destination;

  /// Human-readable place name (e.g. "Karen Shopping Centre").
  ///
  /// Null for journeys created before the field existed, and for clients that
  /// still omit it. Read [destinationLabel] rather than this field when
  /// displaying a destination.
  final String? destinationName;

  /// Formatted address from the place provider. Frequently far coarser than the
  /// place itself (Google returns "Nairobi, Kenya" for some POIs), so it is
  /// secondary information — see [destinationLabel].
  final String destinationAddress;
  final int lagThresholdMeters;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startTime;
  final List<Participant>? participants;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Future start instant for scheduled journeys; null = start-now journey.
  final DateTime? scheduledFor;

  /// Scheduled journeys only: the backend starts the journey automatically
  /// at [scheduledFor] instead of nudging the leader.
  final bool autoStart;

  const Journey({
    required this.id,
    this.inviteCode,
    required this.name,
    required this.leaderId,
    required this.status,
    required this.destination,
    this.destinationName,
    required this.destinationAddress,
    required this.lagThresholdMeters,
    this.createdAt,
    this.updatedAt,
    this.startTime,
    this.participants,
    this.startedAt,
    this.completedAt,
    this.scheduledFor,
    this.autoStart = false,
  });

  /// A journey that is waiting for its scheduled start instant.
  bool get isScheduled =>
      status == JourneyStatus.PENDING && scheduledFor != null;

  /// The destination as it should be shown to a user.
  ///
  /// Prefers the place name and falls back to the formatted address, so
  /// journeys created before [destinationName] existed still render something
  /// meaningful instead of an empty label.
  String get destinationLabel =>
      (destinationName != null && destinationName!.trim().isNotEmpty)
      ? destinationName!.trim()
      : destinationAddress;

  /// Secondary line for a destination, or null when it would merely repeat
  /// [destinationLabel].
  String? get destinationSubtitle {
    final address = destinationAddress.trim();
    if (address.isEmpty || address == destinationLabel) return null;
    return address;
  }

  @override
  List<Object?> get props => [
    id,
    inviteCode,
    name,
    leaderId,
    status,
    destination,
    destinationName,
    destinationAddress,
    lagThresholdMeters,
    createdAt,
    updatedAt,
    startTime,
    participants,
    startedAt,
    completedAt,
    scheduledFor,
    autoStart,
  ];
}

class Participant extends Equatable {
  final String id;
  final String userId;
  final String journeyId;
  final String role;
  final String status;
  final String? invitedBy;
  final String? connectionStatus;
  final DateTime? joinedAt;
  final String? displayName;

  const Participant({
    required this.id,
    required this.userId,
    required this.journeyId,
    required this.role,
    required this.status,
    this.invitedBy,
    this.connectionStatus,
    this.joinedAt,
    this.displayName,
  });

  @override
  List<Object?> get props => [
    id,
    userId,
    journeyId,
    role,
    status,
    invitedBy,
    connectionStatus,
    joinedAt,
    displayName,
  ];
}
