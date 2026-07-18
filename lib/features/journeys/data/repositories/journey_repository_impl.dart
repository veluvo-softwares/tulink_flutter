import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_exceptions.dart';
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
    DateTime? scheduledFor,
    bool autoStart = false,
  }) async {
    try {
      final journey = await remoteDataSource.createJourney(
        name: name,
        latitude: latitude,
        longitude: longitude,
        destinationAddress: destinationAddress,
        lagThresholdMeters: lagThresholdMeters,
        scheduledFor: scheduledFor,
        autoStart: autoStart,
      );
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to create journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
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
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to get journey details',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
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
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to get active journeys',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> joinJourneyByCode(String inviteCode) async {
    try {
      final journey = await remoteDataSource.joinJourneyByCode(inviteCode);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              (e.response?.data is Map<String, dynamic>
                  ? (e.response?.data as Map<String, dynamic>)['message']
                        ?.toString()
                  : null) ??
              'Failed to join journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> startJourney(String journeyId) async {
    try {
      final journey = await remoteDataSource.startJourney(journeyId);
      return (data: journey, failure: null);
    } on AlreadyInActiveJourneyException catch (e) {
      // Single-active-journey enforcement (BE-FIX-3): the data source already
      // parsed the 409 envelope; translate it to a domain Failure that carries
      // activeJourneyId so the UI can offer an end-it-and-start-this switch.
      return (
        data: null,
        failure: AlreadyInActiveJourneyFailure(
          activeJourneyId: e.activeJourneyId,
          message: e.message ?? 'You already have an active journey.',
        ),
      );
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to start journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> updateJourney(
    String journeyId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final journey = await remoteDataSource.updateJourney(
        journeyId,
        updateData,
      );
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to update journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> endJourney(String journeyId) async {
    try {
      final journey = await remoteDataSource.endJourney(journeyId);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to start journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<bool>> cancelJourney(String journeyId) async {
    try {
      await remoteDataSource.cancelJourney(journeyId);
      return (data: true, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to cancel journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<bool>> leaveJourney(String journeyId) async {
    try {
      await remoteDataSource.leaveJourney(journeyId);
      return (data: true, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to leave journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }
}
