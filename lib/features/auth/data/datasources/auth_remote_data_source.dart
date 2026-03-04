import 'package:tulink_flutter/features/auth/data/models/user_model.dart';
import 'package:tulink_flutter/features/auth/data/services/auth_api_service.dart';

/// Remote data source for authentication
/// Now focuses purely on executing service calls and mapping results to Domain Entities
/// Zero hardcoded strings - all endpoints are defined in AuthApiService
abstract class AuthRemoteDataSource {
  /// Sign in with email and password
  Future<({UserModel user, String token, String? refreshToken})> signIn({
    required String email,
    required String password,
  });

  /// Sign up with email, password and name
  Future<({UserModel user, String token, String? refreshToken})> signUp({
    required String email,
    required String password,
    required String name,
  });

  /// Sign out the current user
  Future<void> signOut();

  /// Get currently signed in user
  Future<UserModel> getCurrentUser();

  /// Refresh authentication token
  Future<String> refreshToken();

  /// Send password reset email
  Future<void> resetPassword({required String email});

  /// Verify email address
  Future<void> verifyEmail({required String token});

  /// Update user profile
  Future<UserModel> updateProfile({
    String? name,
    String? profilePicture,
  });

  /// Delete user account
  Future<void> deleteAccount();
}

/// Implementation of AuthRemoteDataSource using AuthApiService
/// Pure data mapping layer with no business logic
/// Single responsibility: Execute API calls and map responses to domain entities
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  /// Constructor takes AuthApiService dependency
  AuthRemoteDataSourceImpl(this._authApiService);

  final AuthApiService _authApiService;

  @override
  Future<({UserModel user, String token, String? refreshToken})> signIn({
    required String email,
    required String password,
  }) async {
    // Execute API call through service
    final response = await _authApiService.signIn({
      'email': email,
      'password': password,
    });

    // Backend response format: { "success": true, "data": { "user": {...}, "tokens": { "idToken": "...", "refreshToken": "..." } } }
    final responseData = response['data'] as Map<String, dynamic>;
    final user = UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
    final tokens = responseData['tokens'] as Map<String, dynamic>;
    final token = tokens['idToken'] as String;
    final refreshToken = tokens['refreshToken'] as String?;

    return (user: user, token: token, refreshToken: refreshToken);
  }

  @override
  Future<({UserModel user, String token, String? refreshToken})> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    // Execute API call through service
    final response = await _authApiService.signUp({
      'email': email,
      'password': password,
      'displayName': name,
    });

    // Backend response format: { "success": true, "data": { "user": {...}, "tokens": { "idToken": "...", "refreshToken": "..." } } }
    final responseData = response['data'] as Map<String, dynamic>;
    final user = UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
    final tokens = responseData['tokens'] as Map<String, dynamic>;
    final token = tokens['idToken'] as String;
    final refreshToken = tokens['refreshToken'] as String?;

    return (user: user, token: token, refreshToken: refreshToken);
  }

  @override
  Future<void> signOut() async {
    // Direct delegation to service
    await _authApiService.signOut();
  }

  @override
  Future<UserModel> getCurrentUser() async {
    // Execute API call and map to domain entity
    final response = await _authApiService.getCurrentUser();
    final responseData = response['data'] as Map<String, dynamic>;
    return UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
  }

  @override
  Future<String> refreshToken() async {
    // Execute API call and extract token
    final response = await _authApiService.refreshToken();
    final responseData = response['data'] as Map<String, dynamic>;
    final tokens = responseData['tokens'] as Map<String, dynamic>;
    return tokens['idToken'] as String;
  }

  @override
  Future<void> resetPassword({required String email}) async {
    // Execute API call through service
    await _authApiService.resetPassword({'email': email});
  }

  @override
  Future<void> verifyEmail({required String token}) async {
    // Execute API call through service
    await _authApiService.verifyEmail({'token': token});
  }

  @override
  Future<UserModel> updateProfile({
    String? name,
    String? profilePicture,
  }) async {
    // Build request data dynamically
    final profileData = <String, dynamic>{};
    if (name != null) profileData['name'] = name;
    if (profilePicture != null) profileData['profile_picture'] = profilePicture;

    // Execute API call and map to domain entity
    final response = await _authApiService.updateProfile(profileData);
    final responseData = response['data'] as Map<String, dynamic>;
    return UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteAccount() async {
    // Direct delegation to service
    await _authApiService.deleteAccount();
  }

  // Additional methods demonstrating the pattern

  /// Get user profile by ID (example of using service's advanced features)
  Future<UserModel> getUserProfile(String userId) async {
    final response = await _authApiService.getUserProfile(userId);
    final responseData = response['data'] as Map<String, dynamic>;
    return UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
  }

  /// Get paginated notifications (example of pagination)
  Future<({List<Map<String, dynamic>> notifications, bool hasMore})> getNotifications({
    int page = 1,
    int limit = 20,
    String? filter,
  }) async {
    final response = await _authApiService.getNotifications(
      page: page,
      limit: limit,
      filter: filter,
    );

    final responseData = response['data'] as Map<String, dynamic>;
    final notifications = (responseData['notifications'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final hasMore = responseData['hasMore'] as bool? ?? false;

    return (notifications: notifications, hasMore: hasMore);
  }

  /// Search users (example of search functionality)
  Future<List<UserModel>> searchUsers({
    required String query,
    List<String>? filters,
    int? page,
    int? limit,
  }) async {
    final response = await _authApiService.searchUsers(
      query: query,
      filters: filters,
      page: page,
      limit: limit,
    );

    final responseData = response['data'] as Map<String, dynamic>;
    final users = (responseData['users'] as List<dynamic>)
        .map((userData) => UserModel.fromJson(userData as Map<String, dynamic>))
        .toList();

    return users;
  }

  /// Update avatar (example of file upload)
  Future<UserModel> updateAvatar({
    required String filePath,
    required String fileName,
    String? metadata,
  }) async {
    final response = await _authApiService.updateAvatar(
      filePath: filePath,
      fileName: fileName,
      metadata: metadata,
    );

    final responseData = response['data'] as Map<String, dynamic>;
    return UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
  }
}