import '../../domain/entities/journey.dart';

class JourneyModel extends Journey {
  const JourneyModel({
    required super.id,
    required super.name,
    required super.leaderId,
    required super.status,
    required super.destination,
    required super.destinationAddress,
    required super.lagThresholdMeters,
    super.createdAt,
    super.updatedAt,
    super.startTime,
    super.participants,
    super.startedAt,
    super.completedAt,
  });

  factory JourneyModel.fromJson(Map<String, dynamic> json) {
    final destination = json['destination'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return JourneyModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      leaderId: json['leaderId']?.toString() ?? '',
      status: _parseStatus(json['status']?.toString()),
      destination: _parseDestination(destination),
      destinationAddress: json['destinationAddress']?.toString() ?? '',
      lagThresholdMeters: (json['lagThresholdMeters'] as num?)?.toInt() ?? 500,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
      startTime: json['startTime'] != null ? DateTime.tryParse(json['startTime'].toString()) : null,
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'].toString()) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'].toString()) : null,
      participants: json['participants'] != null
          ? (json['participants'] as List<dynamic>).map((p) => ParticipantModel.fromJson(p as Map<String, dynamic>)).toList()
          : null,
    );
  }

  /// Parse destination coordinates from various possible formats
  static LatLng _parseDestination(Map<String, dynamic> destination) {
    final latitude = _parseCoordinate(
      destination, 
      ['_latitude', 'latitude', 'lat', 'y'],
      0,
    );
    
    final longitude = _parseCoordinate(
      destination, 
      ['_longitude', 'longitude', 'lng', 'lon', 'x'],
      0,
    );
    
    return LatLng(latitude: latitude, longitude: longitude);
  }

  /// Parse a coordinate value from multiple possible field names
  static double _parseCoordinate(
    Map<String, dynamic> data,
    List<String> fieldNames,
    double defaultValue,
  ) {
    for (final fieldName in fieldNames) {
      final value = data[fieldName];
      if (value != null) {
        if (value is num) {
          return value.toDouble();
        }
        final parsed = double.tryParse(value.toString());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return defaultValue;
  }

  static JourneyStatus _parseStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'ACTIVE':
        return JourneyStatus.ACTIVE;
      case 'PAUSED':
        return JourneyStatus.PAUSED;
      case 'COMPLETED':
        return JourneyStatus.COMPLETED;
      case 'CANCELLED':
        return JourneyStatus.CANCELLED;
      case 'PENDING':
      default:
        return JourneyStatus.PENDING;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'leaderId': leaderId,
      'status': status.name,
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'destinationAddress': destinationAddress,
      'lagThresholdMeters': lagThresholdMeters,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
    };
  }
}

class ParticipantModel extends Participant {
  const ParticipantModel({
    required super.id,
    required super.userId,
    required super.journeyId,
    required super.role,
    required super.status,
    super.invitedBy,
    super.connectionStatus,
    super.joinedAt,
    super.displayName,
  });

  factory ParticipantModel.fromJson(Map<String, dynamic> json) {
    return ParticipantModel(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      journeyId: json['journeyId']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      invitedBy: json['invitedBy']?.toString(),
      connectionStatus: json['connectionStatus']?.toString(),
      joinedAt: json['joinedAt'] != null ? DateTime.tryParse(json['joinedAt'].toString()) : null,
      displayName: json['displayName']?.toString(),
    );
  }
}
