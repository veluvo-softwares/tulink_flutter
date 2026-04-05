import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';
import 'package:tulink_flutter/features/journeys/data/services/journey_api_service.dart';

/// Remote data source for journeys
/// Now focuses purely on executing service calls and mapping results to
/// Domain Entities
/// Zero hardcoded strings - all endpoints are defined in JourneyApiService
abstract class JourneyRemoteDataSource {
  /// Create a new journey
  Future<JourneyModel> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  });

  /// Get journey by ID
  Future<JourneyModel> getJourneyById(String journeyId);

  /// Get all active journeys
  Future<List<JourneyModel>> getActiveJourneys();

  /// Get user's journeys
  Future<List<JourneyModel>> getMyJourneys();

  /// Start a journey
  Future<JourneyModel> startJourney(String journeyId);

  /// Stop a journey
  Future<JourneyModel> stopJourney(String journeyId);

  /// Pause a journey
  Future<JourneyModel> pauseJourney(String journeyId);

  /// Resume a journey
  Future<JourneyModel> resumeJourney(String journeyId);

  /// Update journey details
  Future<JourneyModel> updateJourney(String journeyId, Map<String, dynamic> updateData);

  /// Delete a journey
  Future<void> deleteJourney(String journeyId);
}

/// Implementation of JourneyRemoteDataSource using JourneyApiService
/// Pure data mapping layer with no business logic
/// Single responsibility: Execute API calls and map responses to domain
/// entities
class JourneyRemoteDataSourceImpl implements JourneyRemoteDataSource {
  /// Constructor takes JourneyApiService dependency
  JourneyRemoteDataSourceImpl(this._journeyApiService);

  final JourneyApiService _journeyApiService;

  @override
  Future<JourneyModel> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  }) async {
    // Execute API call through service - this now uses standardized response
    final responseData = await _journeyApiService.createJourney({
      'name': name,
      'destination': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'destinationAddress': destinationAddress,
      'lagThresholdMeters': lagThresholdMeters,
    });

    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<JourneyModel> getJourneyById(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.getJourneyById(journeyId);
    
    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<List<JourneyModel>> getActiveJourneys() async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.getActiveJourneys();
    
    // Parse the response data
    final journeysData = responseData['data'] as List<dynamic>;
    return journeysData
        .map((json) => JourneyModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<JourneyModel>> getMyJourneys() async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.getMyJourneys();
    
    // Parse the response data
    final journeysData = responseData['data'] as List<dynamic>;
    return journeysData
        .map((json) => JourneyModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<JourneyModel> startJourney(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.startJourney(journeyId);
    
    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<JourneyModel> stopJourney(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.stopJourney(journeyId);
    
    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<JourneyModel> pauseJourney(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.pauseJourney(journeyId);
    
    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<JourneyModel> resumeJourney(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _journeyApiService.resumeJourney(journeyId);
    
    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<JourneyModel> updateJourney(
      String journeyId, Map<String, dynamic> updateData) async {
    // Execute API call using standardized response
    final responseData =
        await _journeyApiService.updateJourney(journeyId, updateData);
    
    // Parse the response data
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }

  @override
  Future<void> deleteJourney(String journeyId) async {
    // Direct delegation to service
    await _journeyApiService.deleteJourney(journeyId);
  }
}

