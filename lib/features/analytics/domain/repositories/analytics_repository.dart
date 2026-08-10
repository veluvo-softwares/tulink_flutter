import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import '../../data/models/journey_summary_model.dart';

abstract class AnalyticsRepository {

  /// Get complete journey history with pagination
  Future<Result<List<Journey>>> getJourneyHistory({int limit = 20});

  /// Finished journeys already held on this device, newest-first.
  ///
  /// Separate from [getJourneyHistory] because a Future resolves once and so
  /// cannot both paint immediately and refresh afterwards. Returns an empty
  /// list rather than a failure when nothing is cached — a user with no
  /// history yet is an ordinary state, not an error.
  Future<List<Journey>> getCachedJourneyHistory();

  /// Get analytics for a specific journey
  Future<Result<Journey>> getJourneyAnalytics(String journeyId);

  /// Get summary statistics for a specific journey
  Future<Result<JourneySummaryModel>> getJourneySummary(String journeyId);
}