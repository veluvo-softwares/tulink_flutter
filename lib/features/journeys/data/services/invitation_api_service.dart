import 'package:dio/dio.dart';

import 'package:tulink_flutter/core/network/api_handler.dart';
import 'package:tulink_flutter/core/network/api_query_builder.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';

/// Invitation API service following Retrofit pattern
/// Contains clean method signatures that delegate to ApiHandler
/// All route definitions are centralized in ApiRoutes
/// Zero hardcoded strings in this class
/// Invitation API service following Retrofit pattern
class InvitationApiService {
  /// Constructor that takes a Dio instance
  InvitationApiService(this._dio);

  final Dio _dio;

  /// Send invitation to join a journey
  /// Returns standardized response with invitation data
  Future<Map<String, dynamic>> sendInvitation({
    required String journeyId,
    required Map<String, dynamic> invitationData,
  }) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.journeyInvitations(journeyId),
        data: invitationData,
      ),
      (data) => data,
    );
  }

  /// Get invitation by ID
  /// Returns standardized response with invitation data
  Future<Map<String, dynamic>> getInvitationById(String invitationId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.invitationById(invitationId),
      ),
      (data) => data,
    );
  }

  /// Respond to an invitation (accept/decline)
  /// Returns standardized response with updated invitation data
  Future<Map<String, dynamic>> respondToInvitation({
    required String invitationId,
    required Map<String, dynamic> responseData,
  }) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        ApiRoutes.respondToInvitation(invitationId),
        data: responseData,
      ),
      (data) => data,
    );
  }

  /// Get all invitations for a journey
  /// Returns standardized response with invitation list
  Future<Map<String, dynamic>> getJourneyInvitations(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyInvitations(journeyId),
      ),
      (data) => data,
    );
  }

  /// Get user's invitations (received)
  /// Returns standardized response with invitation list
  Future<Map<String, dynamic>> getMyInvitations() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.myInvitations,
      ),
      (data) => data,
    );
  }

  /// Get pending invitations for user
  /// Returns standardized response with invitation list
  Future<Map<String, dynamic>> getPendingInvitations() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.pendingInvitations,
      ),
      (data) => data,
    );
  }

  /// Get sent invitations from user
  /// Returns standardized response with invitation list
  Future<Map<String, dynamic>> getSentInvitations() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.sentInvitations,
      ),
      (data) => data,
    );
  }

  /// Cancel an invitation
  /// Uses standardized void response format
  Future<void> cancelInvitation(String invitationId) {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.delete<void>(
        ApiRoutes.cancelInvitation(invitationId),
      ),
    );
  }

  /// Resend an invitation
  /// Returns standardized response with updated invitation data
  Future<Map<String, dynamic>> resendInvitation(String invitationId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.resendInvitation(invitationId),
      ),
      (data) => data,
    );
  }

  /// Get participant by ID
  /// Returns standardized response with participant data
  Future<Map<String, dynamic>> getParticipantById(String participantId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.participantById(participantId),
      ),
      (data) => data,
    );
  }

  /// Get participant location
  /// Returns standardized response with location data
  Future<Map<String, dynamic>> getParticipantLocation(String participantId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.participantLocation(participantId),
      ),
      (data) => data,
    );
  }

  /// Update participant status
  /// Returns standardized response with updated participant data
  Future<Map<String, dynamic>> updateParticipantStatus({
    required String participantId,
    required Map<String, dynamic> statusData,
  }) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        ApiRoutes.participantStatus(participantId),
        data: statusData,
      ),
      (data) => data,
    );
  }

  /// Search users for invitations
  /// Returns standardized response with user list
  Future<Map<String, dynamic>> searchUsers({
    required String query,
    List<String>? filters,
    int? page,
    int? limit,
  }) {
    final endpoint = ApiQueryBuilder.search(
      ApiRoutes.userSearch,
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

  /// Get paginated invitations with filters
  Future<Map<String, dynamic>> getInvitations({
    int page = 1,
    int limit = 20,
    String? status,
    String? type,
  }) {
    final endpoint = ApiQueryBuilder.paginated(
      ApiRoutes.invitations,
      page: page,
      limit: limit,
    );

    // Build query parameters
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (type != null) queryParams['type'] = type;

    final finalEndpoint = queryParams.isNotEmpty
        ? '$endpoint${endpoint.contains('?') ? '&' : '?'}${
            queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : endpoint;

    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(finalEndpoint),
      (data) => data,
    );
  }

  /// Bulk cancel invitations
  /// Uses standardized void response format
  Future<void> bulkCancelInvitations(List<String> invitationIds) {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.delete<void>(
        ApiRoutes.invitations,
        data: {'invitationIds': invitationIds},
      ),
    );
  }

  /// Get invitation statistics for a journey
  /// Returns standardized response with statistics data
  Future<Map<String, dynamic>> getInvitationStats(String journeyId) {
    final endpoint = '${ApiRoutes.journeyInvitations(journeyId)}/stats';
    
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(endpoint),
      (data) => data,
    );
  }

  /// Health check for invitation service
  Future<Map<String, dynamic>> healthCheck() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiRoutes.health),
      (data) => data,
    );
  }
}
