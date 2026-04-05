import 'package:dio/dio.dart';

import 'package:tulink_flutter/core/network/api_handler.dart';
import 'package:tulink_flutter/core/network/api_query_builder.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';

/// Journey API service following Retrofit pattern
/// Contains clean method signatures that delegate to ApiHandler
/// All route definitions are centralized in ApiRoutes
/// Zero hardcoded strings in this class
/// Journey API service following Retrofit pattern
class JourneyApiService {
  /// Constructor that takes a Dio instance
  JourneyApiService(this._dio);

  final Dio _dio;

  /// Create a new journey
  /// Returns standardized response with journey data
  Future<Map<String, dynamic>> createJourney(Map<String, dynamic> journeyData) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.journeys,
        data: journeyData,
      ),
      (data) => data,
    );
  }

  /// Get journey by ID
  /// Returns standardized response with journey data
  Future<Map<String, dynamic>> getJourneyById(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyById(journeyId),
      ),
      (data) => data,
    );
  }

  /// Get active journeys
  /// Returns standardized response with list of journeys
  Future<Map<String, dynamic>> getActiveJourneys() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.activeJourneys,
      ),
      (data) => data,
    );
  }

  /// Get user's journeys
  /// Returns standardized response with list of user's journeys
  Future<Map<String, dynamic>> getMyJourneys() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.myJourneys,
      ),
      (data) => data,
    );
  }

  /// Start a journey
  /// Returns standardized response with updated journey data
  Future<Map<String, dynamic>> startJourney(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.startJourney(journeyId),
      ),
      (data) => data,
    );
  }

  /// Stop a journey
  /// Returns standardized response with updated journey data
  Future<Map<String, dynamic>> stopJourney(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.stopJourney(journeyId),
      ),
      (data) => data,
    );
  }

  /// Pause a journey
  /// Returns standardized response with updated journey data
  Future<Map<String, dynamic>> pauseJourney(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.pauseJourney(journeyId),
      ),
      (data) => data,
    );
  }

  /// Resume a journey
  /// Returns standardized response with updated journey data
  Future<Map<String, dynamic>> resumeJourney(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.resumeJourney(journeyId),
      ),
      (data) => data,
    );
  }

  /// Get journey participants
  /// Returns standardized response with participant list
  Future<Map<String, dynamic>> getJourneyParticipants(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyParticipants(journeyId),
      ),
      (data) => data,
    );
  }

  /// Get journey invitations
  /// Returns standardized response with invitation list
  Future<Map<String, dynamic>> getJourneyInvitations(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyInvitations(journeyId),
      ),
      (data) => data,
    );
  }

  /// Get journey routes/path
  /// Returns standardized response with route data
  Future<Map<String, dynamic>> getJourneyRoutes(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyRoutes(journeyId),
      ),
      (data) => data,
    );
  }

  /// Get journey progress
  /// Returns standardized response with progress data
  Future<Map<String, dynamic>> getJourneyProgress(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyProgress(journeyId),
      ),
      (data) => data,
    );
  }

  /// Remove participant from journey
  /// Uses standardized void response format
  Future<void> removeParticipant(String journeyId, String participantId) {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.delete<void>(
        ApiRoutes.removeParticipant(journeyId, participantId),
      ),
    );
  }

  /// Update journey details
  /// Returns standardized response with updated journey data
  Future<Map<String, dynamic>> updateJourney(
    String journeyId,
    Map<String, dynamic> updateData,
  ) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.put<Map<String, dynamic>>(
        ApiRoutes.journeyById(journeyId),
        data: updateData,
      ),
      (data) => data,
    );
  }

  /// Delete journey
  /// Uses standardized void response format
  Future<void> deleteJourney(String journeyId) {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.delete<void>(
        ApiRoutes.journeyById(journeyId),
      ),
    );
  }

  /// Get paginated journeys with filters
  Future<Map<String, dynamic>> getJourneys({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
  }) {
    final endpoint = ApiQueryBuilder.paginated(
      ApiRoutes.journeys,
      page: page,
      limit: limit,
    );

    // Build query parameters
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;

    final finalEndpoint = queryParams.isNotEmpty
        ? '$endpoint${endpoint.contains('?') ? '&' : '?'}${
            queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : endpoint;

    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(finalEndpoint),
      (data) => data,
    );
  }

  /// Search journeys by location or name
  Future<Map<String, dynamic>> searchJourneys({
    required String query,
    List<String>? filters,
    int? page,
    int? limit,
  }) {
    final endpoint = ApiQueryBuilder.search(
      ApiRoutes.journeys,
      query: query,
      filters: filters,
      page: page,
      limit: limit,
    );

    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(endpoint),
      (data) => data,
    );
  }

  /// Health check for journey service
  Future<Map<String, dynamic>> healthCheck() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiRoutes.health),
      (data) => data,
    );
  }
}
