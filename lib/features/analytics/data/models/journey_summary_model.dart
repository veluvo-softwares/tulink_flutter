class JourneySummaryModel {
  final String journeyId;
  final double totalDistanceMetres;
  final double averageSpeedMs; // metres per second — convert for display
  final double totalDurationSeconds;
  final int lagAlertCount;
  final int participantCount;
  final DateTime? startTime;
  final DateTime? endTime;

  const JourneySummaryModel({
    required this.journeyId,
    required this.totalDistanceMetres,
    required this.averageSpeedMs,
    required this.totalDurationSeconds,
    required this.lagAlertCount,
    required this.participantCount,
    this.startTime,
    this.endTime,
  });

  factory JourneySummaryModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is Map && value.containsKey('_seconds')) {
        return DateTime.fromMillisecondsSinceEpoch(
          ((value['_seconds'] as num) * 1000).toInt(),
        );
      }
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return JourneySummaryModel(
      journeyId: json['journeyId']?.toString() ?? '',
      totalDistanceMetres:
          (json['totalDistance'] as num?)?.toDouble() ?? 0.0,
      averageSpeedMs: (json['averageSpeed'] as num?)?.toDouble() ?? 0.0,
      totalDurationSeconds:
          (json['totalDuration'] as num?)?.toDouble() ?? 0.0,
      lagAlertCount: (json['lagAlertCount'] as num?)?.toInt() ?? 0,
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
      startTime: parseTimestamp(json['startTime']),
      endTime: parseTimestamp(json['endTime']),
    );
  }

  /// Formatted distance string
  String get distanceDisplay {
    if (totalDistanceMetres >= 1000) {
      return '${(totalDistanceMetres / 1000).toStringAsFixed(1)} km';
    }
    return '${totalDistanceMetres.toStringAsFixed(0)} m';
  }

  /// Formatted duration string
  String get durationDisplay {
    final duration = Duration(seconds: totalDurationSeconds.toInt());
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Average speed in km/h
  String get avgSpeedDisplay {
    final kmh = averageSpeedMs * 3.6;
    return '${kmh.toStringAsFixed(1)} km/h';
  }
}
