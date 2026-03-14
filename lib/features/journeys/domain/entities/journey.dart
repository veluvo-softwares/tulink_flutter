import 'package:equatable/equatable.dart';

enum JourneyStatus { PENDING, ACTIVE, COMPLETED, CANCELLED }

class LatLng extends Equatable {
  final double latitude;
  final double longitude;

  const LatLng({required this.latitude, required this.longitude});

  @override
  List<Object?> get props => [latitude, longitude];
}

class Journey extends Equatable {
  final String id;
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

  const Journey({
    required this.id,
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
  });

  @override
  List<Object?> get props => [
        id,
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

  const Participant({
    required this.id,
    required this.userId,
    required this.journeyId,
    required this.role,
    required this.status,
    this.invitedBy,
    this.connectionStatus,
    this.joinedAt,
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
      ];
}
