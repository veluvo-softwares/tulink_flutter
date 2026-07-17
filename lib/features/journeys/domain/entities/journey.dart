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

  @override
  List<Object?> get props => [
    id,
    inviteCode,
    name,
    leaderId,
    status,
    destination,
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
