import 'package:equatable/equatable.dart';

/// A navigation snapshot recovered from disk before live tracking resumes.
///
/// [RouteProgress] cannot be rebuilt from storage — it carries the current
/// [Maneuver], which is only meaningful against a loaded route. But the
/// numbers a driver actually reads while glancing at the screen (how far, how
/// long) are persisted every few seconds and were previously discarded on
/// restore, leaving "-- km / Calculating ETA" on screen for as long as it took
/// to acquire a GPS fix and fetch a fresh route.
///
/// This is deliberately not a [RouteProgress]: it is last-known, not live, and
/// the type difference keeps that distinction visible at every call site.
class LastKnownProgress extends Equatable {
  const LastKnownProgress({
    required this.distanceRemainingMetres,
    required this.durationRemainingSeconds,
    required this.recordedAt,
    this.currentSegmentIndex,
    this.snappedLatitude,
    this.snappedLongitude,
  });

  /// Rebuilds from the map written by NavigationProvider._persistProgress.
  /// Returns null when the entry predates this schema or is unusable, so a
  /// partial write can never surface as a confident-looking zero.
  static LastKnownProgress? fromStorage(Map<String, dynamic>? json) {
    if (json == null) return null;

    final distance = (json['distanceRemainingMetres'] as num?)?.toDouble();
    final duration = (json['durationRemainingSeconds'] as num?)?.toDouble();
    if (distance == null || duration == null) return null;

    final recordedAtRaw = json['positionRecordedAt'] as String?;
    final recordedAt = recordedAtRaw == null
        ? null
        : DateTime.tryParse(recordedAtRaw);
    // Without a timestamp we cannot say how stale this is, and unlabelled
    // stale figures are worse than none.
    if (recordedAt == null) return null;

    return LastKnownProgress(
      distanceRemainingMetres: distance,
      durationRemainingSeconds: duration,
      recordedAt: recordedAt,
      currentSegmentIndex: (json['currentSegmentIndex'] as num?)?.toInt(),
      snappedLatitude: (json['snappedLatitude'] as num?)?.toDouble(),
      snappedLongitude: (json['snappedLongitude'] as num?)?.toDouble(),
    );
  }

  final double distanceRemainingMetres;
  final double durationRemainingSeconds;

  /// When the snapshot was taken, in UTC. Drives the staleness label.
  final DateTime recordedAt;

  final int? currentSegmentIndex;
  final double? snappedLatitude;
  final double? snappedLongitude;

  Duration ageAt(DateTime now) => now.toUtc().difference(recordedAt.toUtc());

  /// Below this, a snapshot is treated as current and shown unlabelled — the
  /// beacon writes every 5s, so a few seconds old is effectively live and
  /// flagging it would be noise on every single resume.
  static const Duration freshFor = Duration(seconds: 60);

  bool isStaleAt(DateTime now) => ageAt(now) >= freshFor;

  @override
  List<Object?> get props => [
    distanceRemainingMetres,
    durationRemainingSeconds,
    recordedAt,
    currentSegmentIndex,
    snappedLatitude,
    snappedLongitude,
  ];
}
