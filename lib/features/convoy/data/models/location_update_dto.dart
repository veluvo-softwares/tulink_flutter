/// Data Transfer Object for publishing location updates to the backend
/// Matches the POST /locations API contract exactly
class LocationUpdateDto {
  const LocationUpdateDto({
    required this.journeyId,
    required this.location,
    required this.timestamp,
    this.accuracy,
    this.altitude,
    this.heading,
    this.speed,
    this.metadata,
  });

  /// Journey ID this update belongs to
  final String journeyId;

  /// Location coordinates
  final LocationCoordinatesDto location;

  /// Timestamp in milliseconds since epoch
  final int timestamp;

  /// Position accuracy in meters
  final double? accuracy;

  /// Altitude in meters above sea level
  final double? altitude;

  /// Heading in degrees (0-360)
  final double? heading;

  /// Speed in meters per second
  final double? speed;

  /// Additional metadata (battery, movement status, etc.)
  final Map<String, dynamic>? metadata;

  /// Create from JSON
  factory LocationUpdateDto.fromJson(Map<String, dynamic> json) {
    return LocationUpdateDto(
      journeyId: json['journeyId']?.toString() ?? '',
      location: LocationCoordinatesDto.fromJson(
        json['location'] as Map<String, dynamic>? ?? {},
      ),
      timestamp:
          (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      accuracy: json['accuracy'] != null
          ? (json['accuracy'] as num).toDouble()
          : null,
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
      heading: json['heading'] != null
          ? (json['heading'] as num).toDouble()
          : null,
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'journeyId': journeyId,
      'location': location.toJson(),
      'timestamp': timestamp,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Create location update from position data
  factory LocationUpdateDto.fromPosition({
    required String journeyId,
    required double latitude,
    required double longitude,
    required int timestamp,
    double? accuracy,
    double? altitude,
    double? heading,
    double? speed,
    Map<String, dynamic>? metadata,
  }) {
    return LocationUpdateDto(
      journeyId: journeyId,
      location: LocationCoordinatesDto(
        latitude: latitude,
        longitude: longitude,
      ),
      timestamp: timestamp,
      accuracy: accuracy,
      altitude: altitude,
      // Geolocator uses -1 when a simulator/device cannot determine these
      // values. The backend correctly rejects negative heading/speed values,
      // so omit unknown sensor readings rather than poisoning the publish loop.
      heading: heading != null && heading >= 0 && heading <= 360
          ? heading
          : null,
      speed: speed != null && speed >= 0 ? speed : null,
      metadata: metadata,
    );
  }
}

/// Location coordinates DTO matching API contract
class LocationCoordinatesDto {
  const LocationCoordinatesDto({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  /// Create from JSON
  factory LocationCoordinatesDto.fromJson(Map<String, dynamic> json) {
    return LocationCoordinatesDto(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {'latitude': latitude, 'longitude': longitude};
  }
}

/// Response DTO for latest convoy locations endpoint
class ConvoySnapshotDto {
  const ConvoySnapshotDto({
    required this.locations,
    this.destination,
    this.destinationAddress,
  });

  /// Map of user ID to their latest position
  final Map<String, dynamic> locations;

  /// Destination coordinates
  final LocationCoordinatesDto? destination;

  /// Human-readable destination address
  final String? destinationAddress;

  /// Create from JSON
  factory ConvoySnapshotDto.fromJson(Map<String, dynamic> json) {
    // Backend sends 'participants' key; fall back to 'locations' for compat.
    final raw = json['participants'] ?? json['locations'];
    return ConvoySnapshotDto(
      locations: raw is Map ? raw.cast<String, dynamic>() : {},
      destination: json['destination'] != null
          ? LocationCoordinatesDto.fromJson(
              json['destination'] as Map<String, dynamic>,
            )
          : null,
      destinationAddress: json['destinationAddress']?.toString(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'locations': locations,
      if (destination != null) 'destination': destination!.toJson(),
      if (destinationAddress != null) 'destinationAddress': destinationAddress,
    };
  }
}
