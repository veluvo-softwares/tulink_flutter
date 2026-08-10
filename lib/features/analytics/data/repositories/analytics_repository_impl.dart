import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/services/offline_storage_service.dart';
import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../datasources/analytics_remote_data_source.dart';
import '../models/journey_summary_model.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsRemoteDataSource remoteDataSource;

  /// Optional so existing construction sites keep working; when absent the
  /// repository behaves exactly as it did before.
  final OfflineStorageService? offlineStorage;
  final Future<String?> Function()? currentUserId;

  AnalyticsRepositoryImpl({
    required this.remoteDataSource,
    this.offlineStorage,
    this.currentUserId,
  });

  /// Finished journeys held on device, newest-first.
  ///
  /// Read separately from [getJourneyHistory] rather than folded into it: a
  /// Future resolves once, so a single call cannot both paint immediately and
  /// refresh afterwards. Callers show this first, then reconcile.
  @override
  Future<List<Journey>> getCachedJourneyHistory() async {
    final userId = await _resolveUserId();
    final storage = offlineStorage;
    if (storage == null || userId == null) return const [];

    final journeys = <Journey>[];
    for (final json in storage.loadJourneyHistory(userId)) {
      try {
        journeys.add(JourneyModel.fromJson(json));
      } catch (error) {
        // One unreadable entry must not cost the whole list.
        print('⚠️ Skipping corrupt cached journey: $error');
      }
    }
    return journeys;
  }

  @override
  Future<Result<List<Journey>>> getJourneyHistory({int limit = 20}) async {
    try {
      final journeys = await remoteDataSource.getJourneyHistory(limit: limit);
      await _cacheJourneyHistory(journeys);
      return (data: journeys, failure: null);
    } on DioException catch (e) {
      final errorMessage = e.response?.data?['message']?.toString() ?? 'Failed to get journey history';
      return (
        data: null,
        failure: ServerFailure(message: errorMessage),
      );
    } catch (e) {
      return (
        data: null,
        failure: ServerFailure(message: e.toString()),
      );
    }
  }

  Future<void> _cacheJourneyHistory(List<Journey> journeys) async {
    final userId = await _resolveUserId();
    final storage = offlineStorage;
    if (storage == null || userId == null) return;

    final encoded = <Map<String, dynamic>>[];
    for (final journey in journeys) {
      if (journey is! JourneyModel) continue;
      try {
        encoded.add(journey.toJson());
      } catch (error) {
        print('⚠️ Skipping unencodable journey for cache: $error');
      }
    }
    // Retention is applied inside saveJourneyHistory.
    await storage.saveJourneyHistory(userId, encoded);
  }

  Future<String?> _resolveUserId() async {
    final resolve = currentUserId;
    if (resolve == null) return null;
    return resolve();
  }

  @override
  Future<Result<Journey>> getJourneyAnalytics(String journeyId) async {
    try {
      final journey = await remoteDataSource.getJourneyAnalytics(journeyId);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message: e.response?.data?['message']?.toString() ??
              'Failed to get journey analytics',
        ),
      );
    } catch (e) {
      return (
        data: null,
        failure: ServerFailure(message: e.toString()),
      );
    }
  }

  @override
  Future<Result<JourneySummaryModel>> getJourneySummary(
    String journeyId,
  ) async {
    try {
      final summary = await remoteDataSource.getJourneySummary(journeyId);
      if (summary == null) {
        return (
          data: null,
          failure: ServerFailure(message: 'Journey summary not available'),
        );
      }
      return (data: summary, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message: e.response?.data?['message']?.toString() ??
              'Failed to get journey summary',
        ),
      );
    } catch (e) {
      return (
        data: null,
        failure: ServerFailure(message: e.toString()),
      );
    }
  }
}