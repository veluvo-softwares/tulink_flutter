import 'package:dio/dio.dart';

import 'package:tulink_flutter/core/network/api_endpoints.dart';
import 'package:tulink_flutter/core/network/api_handler.dart';

/// Authentication API service following Retrofit pattern
/// Contains clean method signatures that delegate to ApiHandler
/// All route definitions are centralized in ApiEndpoints
/// Zero hardcoded strings in this class
class AuthApiService {
  AuthApiService(this._dio);

  final Dio _dio;

  /// Sign in with email and password
  Future<Map<String, dynamic>> signIn(Map<String, dynamic> credentials) {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiEndpoints.signIn,
        data: credentials,
      ),
      (data) => data,
    );
  }

  /// Sign up with email, password and name
  Future<Map<String, dynamic>> signUp(Map<String, dynamic> userDetails) {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiEndpoints.signUp,
        data: userDetails,
      ),
      (data) => data,
    );
  }

  /// Sign out the current user
  Future<void> signOut() {
    return ApiHandler.performVoidApiCall(
      () => _dio.post<void>(ApiEndpoints.signOut),
    );
  }

  /// Get currently signed in user
  Future<Map<String, dynamic>> getCurrentUser() {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiEndpoints.currentUser),
      (data) => data,
    );
  }

  /// Refresh authentication token
  Future<Map<String, dynamic>> refreshToken() {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(ApiEndpoints.refreshToken),
      (data) => data,
    );
  }

  /// Send password reset email
  Future<void> resetPassword(Map<String, dynamic> emailData) {
    return ApiHandler.performVoidApiCall(
      () => _dio.post<void>(
        ApiEndpoints.resetPassword,
        data: emailData,
      ),
    );
  }

  /// Verify email address
  Future<void> verifyEmail(Map<String, dynamic> tokenData) {
    return ApiHandler.performVoidApiCall(
      () => _dio.post<void>(
        ApiEndpoints.verifyEmail,
        data: tokenData,
      ),
    );
  }

  /// Update user profile
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profileData) {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        ApiEndpoints.updateProfile,
        data: profileData,
      ),
      (data) => data,
    );
  }

  /// Delete user account
  Future<void> deleteAccount() {
    return ApiHandler.performVoidApiCall(
      () => _dio.delete<void>(ApiEndpoints.deleteAccount),
    );
  }

  // Example of dynamic endpoints using ApiEndpoints helper methods

  /// Get user profile by ID (using dynamic endpoint construction)
  Future<Map<String, dynamic>> getUserProfile(String userId) {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiEndpoints.userById(userId),
      ),
      (data) => data,
    );
  }

  /// Get paginated notifications
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 20,
    String? filter,
  }) {
    final endpoint = ApiEndpoints.paginated(
      ApiEndpoints.notifications,
      page: page,
      limit: limit,
    );

    // Add filter as query parameter if provided
    final finalEndpoint = filter != null
        ? '$endpoint${endpoint.contains('?') ? '&' : '?'}filter=$filter'
        : endpoint;

    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(finalEndpoint),
      (data) => data,
    );
  }

  /// Search users (using search helper method)
  Future<Map<String, dynamic>> searchUsers({
    required String query,
    List<String>? filters,
    int? page,
    int? limit,
  }) {
    final endpoint = ApiEndpoints.search(
      ApiEndpoints.userSearch,
      query: query,
      filters: filters,
      page: page,
      limit: limit,
    );

    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(endpoint),
      (data) => data,
    );
  }

  /// Upload avatar (multipart example)
  Future<Map<String, dynamic>> updateAvatar({
    required String filePath,
    required String fileName,
    String? metadata,
  }) {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () async {
        final formData = FormData.fromMap({
          'avatar': await MultipartFile.fromFile(filePath, filename: fileName),
          if (metadata != null) 'metadata': metadata,
        });

        return _dio.post<Map<String, dynamic>>(
          '${ApiEndpoints.updateProfile}/avatar',
          data: formData,
        );
      },
      (data) => data,
    );
  }

  /// Download file (stream response example)
  Future<Response<ResponseBody>> downloadFile(String fileId) {
    return _dio.get<ResponseBody>(
      ApiEndpoints.downloadFile(fileId),
      options: Options(responseType: ResponseType.stream),
    );
  }
}