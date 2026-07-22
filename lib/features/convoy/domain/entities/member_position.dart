import 'package:equatable/equatable.dart';

/// Represents a single convoy member's position snapshot
/// This is an immutable domain entity representing core business data
class MemberPosition extends Equatable {
  const MemberPosition({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.heading,
    this.speed,
    this.altitude,
    this.batteryLevel,
    this.isMoving = false,
    this.statusChange,
    this.sequenceNumber,
    this.priority,
    this.connectionState,
    this.lastSeenAt,
  });

  /// Unique identifier for the convoy member
  final String userId;

  /// Geographic latitude in degrees
  final double latitude;

  /// Geographic longitude in degrees
  final double longitude;

  /// Timestamp when position was recorded (milliseconds since epoch)
  final int timestamp;

  /// Position accuracy in meters (optional)
  final double? accuracy;

  /// Heading/direction in degrees (0-360, where 0 is north)
  final double? heading;

  /// Speed in meters per second
  final double? speed;

  /// Altitude in meters above sea level
  final double? altitude;

  /// Device battery level (0-100) for convoy coordination metadata
  final int? batteryLevel;

  /// Whether the member is currently moving
  final bool isMoving;

  /// Status change indicator (LAG, ARRIVED, etc.)
  final String? statusChange;

  /// Sequence number for ordering updates
  final int? sequenceNumber;

  /// Priority level for update processing
  final String? priority;
  final String? connectionState;
  final int? lastSeenAt;

  /// Get the age of this position in milliseconds
  int get ageInMilliseconds =>
      DateTime.now().millisecondsSinceEpoch - timestamp;

  /// Get the age of this position as a Duration
  Duration get age => Duration(milliseconds: ageInMilliseconds);

  /// Check if position is stale (older than 30 seconds)
  bool get isStale =>
      connectionState == 'RECONNECTING' ||
      connectionState == 'DISCONNECTED' ||
      ageInMilliseconds > 30000;

  /// Check if position is very stale (older than 60 seconds)
  bool get isVeryStale => ageInMilliseconds > 60000;

  /// Get normalized heading (0-360 degrees)
  double get normalizedHeading {
    if (heading == null) return 0.0;
    var normalized = heading! % 360;
    if (normalized < 0) normalized += 360;
    return normalized;
  }

  /// Get speed in kilometers per hour
  double get speedKmh {
    if (speed == null) return 0.0;
    return speed! * 3.6; // Convert m/s to km/h
  }

  /// Check if member has low battery (below 20%)
  bool get hasLowBattery => batteryLevel != null && batteryLevel! < 20;

  /// Check if member is lagging based on status
  bool get isLagging => statusChange == 'LAG';

  /// Check if member has arrived at destination
  bool get hasArrived => statusChange == 'ARRIVED';

  /// Get member status for display
  String get memberStatus {
    if (hasArrived) return 'ARRIVED';
    if (isLagging) return 'LAG';
    if (isStale) return 'OFFLINE';
    if (isMoving && (speed ?? 0) > 0.5) return 'MOVING';
    return 'STOPPED';
  }

  /// Copy with new values
  MemberPosition copyWith({
    String? userId,
    double? latitude,
    double? longitude,
    int? timestamp,
    double? accuracy,
    double? heading,
    double? speed,
    double? altitude,
    int? batteryLevel,
    bool? isMoving,
    String? statusChange,
    int? sequenceNumber,
    String? priority,
    String? connectionState,
    int? lastSeenAt,
  }) {
    return MemberPosition(
      userId: userId ?? this.userId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      altitude: altitude ?? this.altitude,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isMoving: isMoving ?? this.isMoving,
      statusChange: statusChange ?? this.statusChange,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      priority: priority ?? this.priority,
      connectionState: connectionState ?? this.connectionState,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  @override
  List<Object?> get props => [
    userId,
    latitude,
    longitude,
    timestamp,
    accuracy,
    heading,
    speed,
    altitude,
    batteryLevel,
    isMoving,
    statusChange,
    sequenceNumber,
    priority,
    connectionState,
    lastSeenAt,
  ];

  @override
  String toString() {
    return 'MemberPosition('
        'userId: $userId, '
        'lat: ${latitude.toStringAsFixed(6)}, '
        'lng: ${longitude.toStringAsFixed(6)}, '
        'status: $memberStatus, '
        'speed: ${speedKmh.toStringAsFixed(1)}km/h'
        ')';
  }
}
