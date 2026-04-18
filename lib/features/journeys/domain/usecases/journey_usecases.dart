import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/repositories/journey_repository.dart';

class CreateJourney {
  final JourneyRepository repository;

  CreateJourney(this.repository);

  Future<Result<Journey>> call({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  }) {
    return repository.createJourney(
      name: name,
      latitude: latitude,
      longitude: longitude,
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
    );
  }
}

class GetJourneyById {
  final JourneyRepository repository;

  GetJourneyById(this.repository);

  Future<Result<Journey>> call(String journeyId) {
    return repository.getJourneyById(journeyId);
  }
}

class GetActiveJourneys {
  final JourneyRepository repository;

  GetActiveJourneys(this.repository);

  Future<Result<List<Journey>>> call() {
    return repository.getActiveJourneys();
  }
}

class StartJourney {
  final JourneyRepository repository;

  StartJourney(this.repository);

  Future<Result<Journey>> call(String journeyId) {
    return repository.startJourney(journeyId);
  }
}

class UpdateJourney {
  final JourneyRepository repository;

  UpdateJourney(this.repository);

  Future<Result<Journey>> call({
    required String journeyId,
    required Map<String, dynamic> updateData,
  }) {
    return repository.updateJourney(journeyId, updateData);
  }
}
