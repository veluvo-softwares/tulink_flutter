import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/repositories/journey_repository.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_remote_data_source.dart';

class JourneyRepositoryImpl implements JourneyRepository {
  final JourneyRemoteDataSource remoteDataSource;

  JourneyRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Result<Journey>> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  }) async {
    try {
      final journey = await remoteDataSource.createJourney(
        name: name,
        latitude: latitude,
        longitude: longitude,
        destinationAddress: destinationAddress,
        lagThresholdMeters: lagThresholdMeters,
      );
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message: e.response?.data?['message']?.toString() ?? 
              'Failed to create journey',
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
  Future<Result<Journey>> getJourneyById(String journeyId) async {
    try {
      final journey = await remoteDataSource.getJourneyById(journeyId);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message: e.response?.data?['message']?.toString() ?? 
              'Failed to get journey details',
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
  Future<Result<List<Journey>>> getActiveJourneys() async {
    try {
      final journeys = await remoteDataSource.getActiveJourneys();
      return (data: journeys, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message: e.response?.data?['message']?.toString() ?? 
              'Failed to get active journeys',
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
  Future<Result<Journey>> startJourney(String journeyId) async {
    try {
      final journey = await remoteDataSource.startJourney(journeyId);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message: e.response?.data?['message']?.toString() ?? 
              'Failed to start journey',
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
