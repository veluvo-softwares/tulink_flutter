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
  
  // Navigation-related fields
  final String? routeGeometry;
  final double? estimatedDuration;
  final double? estimatedDistance;
  final DateTime? routeCalculatedAt;
  final List<NavigationStepData>? navigationSteps;

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
    this.startedAt,
    this.completedAt,
    this.routeGeometry,
    this.estimatedDuration,
    this.estimatedDistance,
    this.routeCalculatedAt,
    this.navigationSteps,
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
        startedAt,
        completedAt,
        routeGeometry,
        estimatedDuration,
        estimatedDistance,
        routeCalculatedAt,
        navigationSteps,
      ];

  /// Check if journey has a calculated route
  bool get hasRoute => routeGeometry != null && routeGeometry!.isNotEmpty;

  /// Get formatted estimated duration
  String get formattedEstimatedDuration {
    if (estimatedDuration == null) return 'N/A';
    final duration = Duration(seconds: estimatedDuration!.round());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours == 0) {
      return '${minutes}min';
    }
    return '${hours}h ${minutes}min';
  }

  /// Get formatted estimated distance
  String get formattedEstimatedDistance {
    if (estimatedDistance == null) return 'N/A';
    
    if (estimatedDistance! < 1000) {
      return '${estimatedDistance!.round()} m';
    }
    final km = estimatedDistance! / 1000;
    return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
  }

  /// Get estimated arrival time
  DateTime? get estimatedArrival {
    if (estimatedDuration == null || startedAt == null) return null;
    return startedAt!.add(Duration(seconds: estimatedDuration!.round()));
  }

  /// Copy journey with route information
  Journey copyWithRoute({
    String? routeGeometry,
    double? estimatedDuration,
    double? estimatedDistance,
    DateTime? routeCalculatedAt,
    List<NavigationStepData>? navigationSteps,
  }) {
    return Journey(
      id: id,
      name: name,
      leaderId: leaderId,
      status: status,
      destination: destination,
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startTime: startTime,
      participants: participants,
      startedAt: startedAt,
      completedAt: completedAt,
      routeGeometry: routeGeometry ?? this.routeGeometry,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      routeCalculatedAt: routeCalculatedAt ?? this.routeCalculatedAt,
      navigationSteps: navigationSteps ?? this.navigationSteps,
    );
  }
}

/// Simplified navigation step data for journey entity
/// Used for storing essential navigation information with journey
class NavigationStepData extends Equatable {
  const NavigationStepData({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuverType,
    this.maneuverModifier,
    this.streetName,
  });

  final String instruction;
  final double distance;
  final double duration;
  final String maneuverType;
  final String? maneuverModifier;
  final String? streetName;

  @override
  List<Object?> get props => [
        instruction,
        distance,
        duration,
        maneuverType,
        maneuverModifier,
        streetName,
      ];

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'instruction': instruction,
      'distance': distance,
      'duration': duration,
      'maneuverType': maneuverType,
      'maneuverModifier': maneuverModifier,
      'streetName': streetName,
    };
  }

  /// Create from JSON
  factory NavigationStepData.fromJson(Map<String, dynamic> json) {
    return NavigationStepData(
      instruction: json['instruction'] as String? ?? '',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      maneuverType: json['maneuverType'] as String? ?? '',
      maneuverModifier: json['maneuverModifier'] as String?,
      streetName: json['streetName'] as String?,
    );
  }
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
