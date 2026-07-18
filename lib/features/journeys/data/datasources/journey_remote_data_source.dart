import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/network/api_handler.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';
import 'package:tulink_flutter/core/network/models/api_response.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_exceptions.dart';
import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';

abstract class JourneyRemoteDataSource {
  Future<JourneyModel> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
    DateTime? scheduledFor,
    bool autoStart = false,
  });

  Future<JourneyModel> getJourneyById(String journeyId);

  Future<List<JourneyModel>> getActiveJourneys();

  Future<JourneyModel> joinJourneyByCode(String inviteCode);

  Future<JourneyModel> startJourney(String journeyId);

  Future<JourneyModel> updateJourney(
    String journeyid,
    Map<String, dynamic> updateData,
  );

  Future<JourneyModel> endJourney(String journeyId);

  Future<void> cancelJourney(String journeyId);

  Future<void> leaveJourney(String journeyId);
}

class JourneyRemoteDataSourceImpl implements JourneyRemoteDataSource {
  final Dio dio;

  JourneyRemoteDataSourceImpl({required this.dio});

  @override
  Future<JourneyModel> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
    DateTime? scheduledFor,
    bool autoStart = false,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys',
      data: {
        'name': name,
        'destination': {'latitude': latitude, 'longitude': longitude},
        'destinationAddress': destinationAddress,
        'lagThresholdMeters': lagThresholdMeters,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor.toUtc().toIso8601String(),
        if (scheduledFor != null) 'autoStart': autoStart,
      },
    );

    if (response.statusCode == 201 && response.data != null) {
      final journeyData = response.data!['data'] as Map<String, dynamic>?;
      if (journeyData != null) {
        return JourneyModel.fromJson(journeyData);
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Invalid response format or failed to create journey',
    );
  }

  @override
  Future<JourneyModel> getJourneyById(String journeyId) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/journeys/$journeyId',
    );

    if (response.statusCode == 200 && response.data != null) {
      final journeyData = response.data!['data'] as Map<String, dynamic>?;
      if (journeyData != null) {
        return JourneyModel.fromJson(journeyData);
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Invalid response format or journey not found',
    );
  }

  @override
  Future<List<JourneyModel>> getActiveJourneys() async {
    final response = await dio.get<Map<String, dynamic>>('/journeys/active');

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data!['data'] as List<dynamic>?;
      if (data != null) {
        return data
            .map((json) => JourneyModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Invalid response format or failed to get active journeys',
    );
  }

  @override
  Future<JourneyModel> joinJourneyByCode(String inviteCode) async {
    final normalizedCode = inviteCode.trim().toUpperCase();
    final response = await dio.post<Map<String, dynamic>>(
      ApiRoutes.joinJourneyCode(normalizedCode),
    );

    if (response.statusCode == 200 && response.data != null) {
      final journeyData = response.data!['data'] as Map<String, dynamic>?;
      if (journeyData != null) return JourneyModel.fromJson(journeyData);
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Invalid response format or failed to join journey',
    );
  }

  @override
  Future<JourneyModel> startJourney(String journeyId) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/journeys/$journeyId/start',
      );

      if (response.statusCode == 201 && response.data != null) {
        final journeyData = response.data!['data'] as Map<String, dynamic>?;
        if (journeyData != null) {
          return JourneyModel.fromJson(journeyData);
        }
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Invalid response format or failed to start journey',
      );
    } on DioException catch (e) {
      // Single-active-journey enforcement (BE-FIX-3): a 409 with code
      // ALREADY_IN_ACTIVE_JOURNEY carries the offending activeJourneyId. Parse
      // the backend error envelope here, in the data layer, and raise a typed
      // data exception so the repository maps it to a domain Failure without
      // touching transport details.
      final apiError = ApiHandler.extractApiError(e.response?.data);
      if (apiError?.code == ApiErrorCodes.alreadyInActiveJourney) {
        throw AlreadyInActiveJourneyException(
          activeJourneyId: apiError!.activeJourneyId,
          message: e.response?.data?['message']?.toString(),
        );
      }
      rethrow;
    }
  }

  @override
  Future<JourneyModel> updateJourney(
    String journeyId,
    Map<String, dynamic> updateData,
  ) async {
    final response = await dio.put<Map<String, dynamic>>(
      '/journeys/$journeyId',
      data: updateData,
    );

    if (response.statusCode == 200 && response.data != null) {
      final journeyData = response.data!['data'] as Map<String, dynamic>?;
      if (journeyData != null) {
        return JourneyModel.fromJson(journeyData);
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Invalid response format or failed to update journey',
    );
  }

  @override
  Future<JourneyModel> endJourney(String journeyId) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys/$journeyId/end',
    );

    if (response.statusCode == 201 && response.data != null) {
      final journeyData = response.data!['data'] as Map<String, dynamic>?;
      if (journeyData != null) {
        return JourneyModel.fromJson(journeyData);
      }
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: 'Invalid response format or failed to end journey',
    );
  }

  @override
  Future<void> cancelJourney(String journeyId) async {
    final response = await dio.delete<void>('/journeys/$journeyId');
    if (response.statusCode != 204) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Failed to cancel journey',
      );
    }
  }

  @override
  Future<void> leaveJourney(String journeyId) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys/$journeyId/leave',
    );
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Failed to leave journey',
      );
    }
  }
}
