import 'package:dio/dio.dart';

import 'package:tulink_flutter/core/network/api_routes.dart';
import 'package:tulink_flutter/features/profile/domain/entities/user_preferences.dart';

/// Reads and updates the authenticated user's backend preferences.
class UserPreferencesRemoteDataSource {
  /// Creates a client backed by the shared authenticated HTTP connection.
  const UserPreferencesRemoteDataSource(this._dio);

  final Dio _dio;

  /// Returns the complete preference snapshot stored by the backend.
  Future<UserPreferences> get() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.userPreferences,
    );
    return _fromResponse(response);
  }

  /// Partially updates preferences and returns the resulting snapshot.
  Future<UserPreferences> update({
    bool? followLeaderByDefault,
    bool? voiceNavigationEnabled,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.userPreferences,
      data: {
        if (followLeaderByDefault != null)
          'followLeaderByDefault': followLeaderByDefault,
        if (voiceNavigationEnabled != null)
          'voiceNavigationEnabled': voiceNavigationEnabled,
      },
    );
    return _fromResponse(response);
  }

  UserPreferences _fromResponse(Response<Map<String, dynamic>> response) {
    final data = response.data?['data'];
    if (data is! Map) {
      throw const FormatException('Invalid user preferences');
    }
    final json = data.cast<String, dynamic>();
    final followLeader = json['followLeaderByDefault'];
    final voiceNavigation = json['voiceNavigationEnabled'];
    if (followLeader is! bool || voiceNavigation is! bool) {
      throw const FormatException('Invalid user preferences');
    }
    return UserPreferences(
      followLeaderByDefault: followLeader,
      voiceNavigationEnabled: voiceNavigation,
    );
  }
}
