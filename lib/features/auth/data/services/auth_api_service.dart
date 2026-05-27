import 'package:dio/dio.dart';

import '../../../../core/network/api_routes.dart';
import '../../../../core/network/api_handler.dart';
import '../../../../core/network/api_query_builder.dart';

/// Authentication API service following Retrofit pattern
/// Contains clean method signatures that delegate to ApiHandler
/// All route definitions are centralized in ApiRoutes
/// Zero hardcoded strings in this class
class AuthApiService {
  AuthApiService(this._dio);

  final Dio _dio;

  /// Sign in with email and password
  /// Returns standardized response with user and tokens
  Future<Map<String, dynamic>> signIn(Map<String, dynamic> credentials) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.signIn,
        data: credentials,
      ),
      (data) => data,
    );
  }

  /// Sign up with email, password and name
  /// Returns standardized response with user and tokens
  Future<Map<String, dynamic>> signUp(Map<String, dynamic> userDetails) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        ApiRoutes.signUp,
        data: userDetails,
      ),
      (data) => data,
    );
  }

  /// Sign out the current user
  /// Uses standardized void response format
  Future<void> signOut() {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.post<void>(ApiRoutes.signOut),
    );
  }

  /// Get currently signed in user
  /// Returns standardized response with user data
  Future<Map<String, dynamic>> getCurrentUser() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiRoutes.currentUser),
      (data) => data,
    );
  }

  /// Refresh authentication token
  /// Returns standardized response with new tokens
  Future<Map<String, dynamic>> refreshToken() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(ApiRoutes.refreshToken),
      (data) => data,
    );
  }

  /// Send password reset email
  /// Uses standardized void response format
  Future<void> resetPassword(Map<String, dynamic> emailData) {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.post<void>(
        ApiRoutes.resetPassword,
        data: emailData,
      ),
    );
  }

  /// Verify email address
  /// Uses standardized void response format
  Future<void> verifyEmail(Map<String, dynamic> tokenData) {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.post<void>(
        ApiRoutes.verifyEmail,
        data: tokenData,
      ),
    );
  }

  /// Trigger sending the verification email for the authenticated user.
  Future<void> sendEmailVerification() {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.post<void>(ApiRoutes.sendEmailVerification),
    );
  }

  /// Fetch the live user profile to check emailVerified status (bypasses cache).
  Future<Map<String, dynamic>> checkEmailVerification() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiRoutes.currentUser),
      (data) => data,
    );
  }

  /// Update user profile
  /// Returns standardized response with updated user data
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profileData) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.put<Map<String, dynamic>>(
        ApiRoutes.updateProfile,
        data: profileData,
      ),
      (data) => data,
    );
  }

  /// Delete user account
  /// Uses standardized void response format
  Future<void> deleteAccount() {
    return ApiHandler.performStandardVoidApiCall(
      () => _dio.delete<void>(ApiRoutes.deleteAccount),
    );
  }

  // Example of dynamic endpoints using ApiQueryBuilder helper methods

  /// Get user profile by ID (using dynamic endpoint construction)
  Future<Map<String, dynamic>> getUserProfile(String userId) {
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.userById(userId),
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
    final endpoint = ApiQueryBuilder.paginated(
      ApiRoutes.notifications,
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
    final endpoint = ApiQueryBuilder.search(
      ApiRoutes.userSearch,
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
          '${ApiRoutes.updateProfile}/avatar',
          data: formData,
        );
      },
      (data) => data,
    );
  }

  /// Download file (stream response example)
  Future<Response<ResponseBody>> downloadFile(String fileId) {
    return _dio.get<ResponseBody>(
      ApiRoutes.downloadMedia(fileId),
      options: Options(responseType: ResponseType.stream),
    );
  }

  /// Health check endpoint for API connectivity testing
  Future<Map<String, dynamic>> healthCheck() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiRoutes.health),
      (data) => data,
    );
  }

  /// Get API version information
  Future<Map<String, dynamic>> getApiVersion() {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(ApiRoutes.version),
      (data) => data,
    );
  }
}