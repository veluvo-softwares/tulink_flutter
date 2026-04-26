import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

abstract class JourneyRepository {
  Future<Result<Journey>> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  });

  Future<Result<Journey>> getJourneyById(String journeyId);

  Future<Result<List<Journey>>> getActiveJourneys();

  Future<Result<Journey>> startJourney(String journeyId);

  Future<Result<Journey>> updateJourney(String journeyId, Map<String, dynamic> updateData);

  Future<Result<Journey>> endJourney(String journeyId);
}
