import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

abstract class AnalyticsRepository {
  /// Get recent journeys with optional limit
  Future<Result<List<Journey>>> getRecentJourneys({int? limit});

  /// Get complete journey history with pagination
  Future<Result<List<Journey>>> getJourneyHistory({int limit = 20});

  /// Get analytics for a specific journey
  Future<Result<Journey>> getJourneyAnalytics(String journeyId);
}