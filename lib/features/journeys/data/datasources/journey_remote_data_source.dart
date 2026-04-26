import 'package:dio/dio.dart';
import 'package:tulink_flutter/features/home/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';

abstract class JourneyRemoteDataSource {
  Future<JourneyModel> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  });

  Future<JourneyModel> getJourneyById(String journeyId);

  Future<List<JourneyModel>> getActiveJourneys();

  Future<JourneyModel> startJourney(String journeyId);

  Future<JourneyModel> updateJourney(String journeyid, Map<String, dynamic> updateData);

  Future<JourneyModel> endJourney(String journeyId);
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
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/journeys',
      data: {
        'name': name,
        'destination': {
          'latitude': latitude,
          'longitude': longitude,
        },
        'destinationAddress': destinationAddress,
        'lagThresholdMeters': lagThresholdMeters,
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
    final response = await dio.get<Map<String, dynamic>>('/journeys/$journeyId');

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
  Future<JourneyModel> startJourney(String journeyId) async {
    final response = await dio.post<Map<String, dynamic>>('/journeys/$journeyId/start');

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
  }

  @override
  Future<JourneyModel> updateJourney(String journeyId, Map<String, dynamic> updateData) async {
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
    final response = await dio.post<Map<String, dynamic>>('/journeys/$journeyId/end');

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

  
}
