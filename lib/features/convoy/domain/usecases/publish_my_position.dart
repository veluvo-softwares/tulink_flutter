import '../repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';

/// Use case for publishing current user's position to the convoy
/// Handles rate limiting and metadata collection
class PublishMyPosition {
  const PublishMyPosition(this._repository);

  final ConvoyRepository _repository;

  /// Publish current position to convoy with optional metadata
  /// Rate limited to max 1 update per second to respect server limits
  Future<({bool success, Failure? failure})> call({
    required String journeyId,
    required double latitude,
    required double longitude,
    required int timestamp,
    double? accuracy,
    double? altitude,
    double? heading,
    double? speed,
    int? batteryLevel,
    bool? isMoving,
  }) async {
    // Prepare metadata
    final metadata = <String, dynamic>{
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      if (isMoving != null) 'isMoving': isMoving,
    };

    return _repository.publishMyPosition(
      journeyId: journeyId,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      accuracy: accuracy,
      altitude: altitude,
      heading: heading,
      speed: speed,
      metadata: metadata.isNotEmpty ? metadata : null,
    );
  }
}