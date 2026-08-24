import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

abstract class JourneyRepository {
  Future<Result<Journey>> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    String? destinationName,
    required String destinationAddress,
    required int lagThresholdMeters,
    DateTime? scheduledFor,
    bool autoStart = false,
  });

  Future<Result<Journey>> getJourneyById(String journeyId);

  Future<Result<List<Journey>>> getActiveJourneys();

  /// Active journeys already held on this device.
  ///
  /// Separate from [getActiveJourneys] because a Future resolves once and so
  /// cannot both paint immediately and reconcile afterwards. Returns an empty
  /// list rather than a failure when nothing is cached — having no journey is
  /// an ordinary state, not an error.
  Future<List<Journey>> getCachedActiveJourneys();

  Future<Result<Journey>> joinJourneyByCode(String inviteCode);

  Future<Result<Journey>> startJourney(String journeyId);

  Future<Result<Journey>> updateJourney(
    String journeyId,
    Map<String, dynamic> updateData,
  );

  Future<Result<Journey>> endJourney(String journeyId);

  Future<Result<bool>> cancelJourney(String journeyId);

  Future<Result<bool>> leaveJourney(String journeyId);
}
