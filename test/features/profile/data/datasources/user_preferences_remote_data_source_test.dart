import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';
import 'package:tulink_flutter/features/profile/data/datasources/user_preferences_remote_data_source.dart';

void main() {
  test('loads both preferences from the wrapped API response', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.method, 'GET');
          expect(options.path, ApiRoutes.userPreferences);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'data': {
                  'followLeaderByDefault': false,
                  'voiceNavigationEnabled': true,
                },
              },
            ),
          );
        },
      ),
    );

    final preferences = await UserPreferencesRemoteDataSource(dio).get();

    expect(preferences.followLeaderByDefault, isFalse);
    expect(preferences.voiceNavigationEnabled, isTrue);
  });

  test('patches only the supplied preference', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.method, 'PATCH');
          expect(options.path, ApiRoutes.userPreferences);
          expect(options.data, {'voiceNavigationEnabled': false});
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'data': {
                  'followLeaderByDefault': true,
                  'voiceNavigationEnabled': false,
                },
              },
            ),
          );
        },
      ),
    );

    final preferences = await UserPreferencesRemoteDataSource(
      dio,
    ).update(voiceNavigationEnabled: false);

    expect(preferences.followLeaderByDefault, isTrue);
    expect(preferences.voiceNavigationEnabled, isFalse);
  });
}
