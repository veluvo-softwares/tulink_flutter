import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../datasources/analytics_remote_data_source.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsRemoteDataSource remoteDataSource;

  AnalyticsRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Result<List<Journey>>> getJourneyHistory({int limit = 20}) async {
    try {
      final journeys = await remoteDataSource.getJourneyHistory(limit: limit);
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
}