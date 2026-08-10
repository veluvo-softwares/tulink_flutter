import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/utils/logger.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import '../../data/models/journey_summary_model.dart';
import '../repositories/analytics_repository.dart';


class GetJourneyHistoryUseCase {
  final AnalyticsRepository repository;

  GetJourneyHistoryUseCase(this.repository);

  Future<Result<List<Journey>>> call({int limit = 20}) async {
    return await repository.getJourneyHistory(limit: limit);
  }
}

/// Finished journeys already on this device, for painting the history list
/// before the network answers.
class GetCachedJourneyHistoryUseCase {
  final AnalyticsRepository repository;

  GetCachedJourneyHistoryUseCase(this.repository);

  Future<List<Journey>> call() => repository.getCachedJourneyHistory();
}

class GetJourneyAnalyticsUseCase {
  final AnalyticsRepository repository;

  GetJourneyAnalyticsUseCase(this.repository);

  Future<Result<Journey>> call(String journeyId) async {
    return await repository.getJourneyAnalytics(journeyId);
  }
}

class GetJourneySummaryUseCase {
  final AnalyticsRepository repository;

  GetJourneySummaryUseCase(this.repository);

  Future<Result<JourneySummaryModel>> call(String journeyId) async {
    return await repository.getJourneySummary(journeyId);
  }
}