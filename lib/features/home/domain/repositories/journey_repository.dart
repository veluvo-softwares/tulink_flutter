import '../entities/journey.dart';

abstract class JourneyRepository {
  Future<List<Journey>> getRecentJourneys();
}