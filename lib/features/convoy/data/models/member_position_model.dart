import '../../domain/entities/member_position.dart';

/// Data model for member position with JSON and RTDB serialization
/// Handles conversion between external data formats and domain entities
class MemberPositionModel extends MemberPosition {
  const MemberPositionModel({
    required super.userId,
    required super.latitude,
    required super.longitude,
    required super.timestamp,
    super.accuracy,
    super.heading,
    super.speed,
    super.altitude,
    super.batteryLevel,
    super.isMoving,
    super.statusChange,
    super.sequenceNumber,
    super.priority,
    super.connectionState,
    super.lastSeenAt,
  });

  /// Create from JSON (REST API response format)
  factory MemberPositionModel.fromJson(Map<String, dynamic> json) {
    return MemberPositionModel(
      userId: json['userId'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp:
          _parseTimestamp(json['timestamp']) ??
          DateTime.now().millisecondsSinceEpoch,
      accuracy: json['accuracy'] != null
          ? (json['accuracy'] as num).toDouble()
          : null,
      heading: json['heading'] != null
          ? _normalizeHeading((json['heading'] as num).toDouble())
          : null,
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
      batteryLevel: json['batteryLevel'] as int?,
      isMoving: json['isMoving'] as bool? ?? false,
      statusChange: json['statusChange'] as String?,
      sequenceNumber: json['sequenceNumber'] as int?,
      priority: json['priority'] as String?,
      connectionState: json['connectionState']?.toString(),
      lastSeenAt: _parseTimestamp(json['lastSeenAt']),
    );
  }

  /// Create from Firebase RTDB format
  factory MemberPositionModel.fromRtdb(Map<String, dynamic> rtdbData) {
    // Handle metadata field which might be nested
    final metadata = rtdbData['metadata'] as Map<String, dynamic>? ?? {};

    return MemberPositionModel(
      userId: rtdbData['userId'] as String,
      latitude: (rtdbData['lat'] as num).toDouble(),
      longitude: (rtdbData['lng'] as num).toDouble(),
      timestamp: rtdbData['timestamp'] as int,
      accuracy: rtdbData['accuracy'] != null
          ? (rtdbData['accuracy'] as num).toDouble()
          : null,
      heading: rtdbData['heading'] != null
          ? _normalizeHeading((rtdbData['heading'] as num).toDouble())
          : null,
      speed: rtdbData['speed'] != null
          ? (rtdbData['speed'] as num).toDouble()
          : null,
      altitude: rtdbData['altitude'] != null
          ? (rtdbData['altitude'] as num).toDouble()
          : null,
      batteryLevel: metadata['batteryLevel'] as int?,
      isMoving: metadata['isMoving'] as bool? ?? false,
      statusChange: metadata['statusChange'] as String?,
      sequenceNumber: rtdbData['sequenceNumber'] as int?,
      priority: rtdbData['priority'] as String?,
    );
  }

  /// Convert to JSON format
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
      if (accuracy != null) 'accuracy': accuracy,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (altitude != null) 'altitude': altitude,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      'isMoving': isMoving,
      if (statusChange != null) 'statusChange': statusChange,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (priority != null) 'priority': priority,
      if (connectionState != null) 'connectionState': connectionState,
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt,
    };
  }

  /// Convert to domain entity
  MemberPosition toEntity() {
    return MemberPosition(
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      accuracy: accuracy,
      heading: heading,
      speed: speed,
      altitude: altitude,
      batteryLevel: batteryLevel,
      isMoving: isMoving,
      statusChange: statusChange,
      sequenceNumber: sequenceNumber,
      priority: priority,
      connectionState: connectionState,
      lastSeenAt: lastSeenAt,
    );
  }

  /// Create model from domain entity
  factory MemberPositionModel.fromEntity(MemberPosition entity) {
    return MemberPositionModel(
      userId: entity.userId,
      latitude: entity.latitude,
      longitude: entity.longitude,
      timestamp: entity.timestamp,
      accuracy: entity.accuracy,
      heading: entity.heading,
      speed: entity.speed,
      altitude: entity.altitude,
      batteryLevel: entity.batteryLevel,
      isMoving: entity.isMoving,
      statusChange: entity.statusChange,
      sequenceNumber: entity.sequenceNumber,
      priority: entity.priority,
      connectionState: entity.connectionState,
      lastSeenAt: entity.lastSeenAt,
    );
  }

  /// Normalize heading to 0-360 range
  static double _normalizeHeading(double heading) {
    var normalized = heading % 360;
    if (normalized < 0) normalized += 360;
    return normalized;
  }

  static int? _parseTimestamp(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ??
          DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    return null;
  }

  /// Create a list of models from RTDB snapshot
  static List<MemberPositionModel> fromRtdbSnapshot(
    Map<String, dynamic>? snapshot,
  ) {
    if (snapshot == null) return [];

    final positions = <MemberPositionModel>[];

    for (final entry in snapshot.entries) {
      try {
        final userData = entry.value as Map<String, dynamic>;
        positions.add(MemberPositionModel.fromRtdb(userData));
      } catch (e) {
        // Skip invalid entries and continue processing others
        print('⚠️ Failed to parse member position for ${entry.key}: $e');
      }
    }

    return positions;
  }

  /// Create models map from RTDB snapshot
  static Map<String, MemberPositionModel> mapFromRtdbSnapshot(
    Map<String, dynamic>? snapshot,
  ) {
    if (snapshot == null) return {};

    final positions = <String, MemberPositionModel>{};

    for (final entry in snapshot.entries) {
      try {
        final userData = entry.value as Map<String, dynamic>;
        final position = MemberPositionModel.fromRtdb(userData);
        positions[position.userId] = position;
      } catch (e) {
        // Skip invalid entries and continue processing others
        print('⚠️ Failed to parse member position for ${entry.key}: $e');
      }
    }

    return positions;
  }
}
