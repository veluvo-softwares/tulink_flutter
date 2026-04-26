import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/utils/logger.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import '../repositories/analytics_repository.dart';


class GetJourneyHistoryUseCase {
  final AnalyticsRepository repository;

  GetJourneyHistoryUseCase(this.repository);

  Future<Result<List<Journey>>> call({int limit = 20}) async {
    return await repository.getJourneyHistory(limit: limit);
  }
}

class GetJourneyAnalyticsUseCase {
  final AnalyticsRepository repository;

  GetJourneyAnalyticsUseCase(this.repository);

  Future<Result<Journey>> call(String journeyId) async {
    return await repository.getJourneyAnalytics(journeyId);
  }
}