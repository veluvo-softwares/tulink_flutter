import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import '../../data/models/journey_summary_model.dart';

abstract class AnalyticsRepository {

  /// Get complete journey history with pagination
  Future<Result<List<Journey>>> getJourneyHistory({int limit = 20});

  /// Get analytics for a specific journey
  Future<Result<Journey>> getJourneyAnalytics(String journeyId);

  /// Get summary statistics for a specific journey
  Future<Result<JourneySummaryModel>> getJourneySummary(String journeyId);
}