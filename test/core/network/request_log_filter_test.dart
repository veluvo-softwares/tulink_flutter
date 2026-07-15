import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';
import 'package:tulink_flutter/core/network/request_log_filter.dart';

void main() {
  group('shouldLogRequest', () {
    const credentialPaths = [
      ApiRoutes.signIn,
      ApiRoutes.signUp,
      ApiRoutes.socialSignIn,
      ApiRoutes.refreshToken,
      ApiRoutes.forgotPassword,
      ApiRoutes.resetPassword,
      ApiRoutes.fcmToken,
    ];

    for (final path in credentialPaths) {
      test('suppresses logging for credential endpoint $path', () {
        final options = RequestOptions(path: path);
        // The filter is phase-agnostic: request, response, and error entries
        // for a credential endpoint are all suppressed.
        expect(
          shouldLogRequest(options, const FilterArgs(false, null)),
          isFalse,
        );
        expect(
          shouldLogRequest(
            options,
            const FilterArgs(true, {'idToken': 'fake.jwt.token'}),
          ),
          isFalse,
        );
      });
    }

    test('keeps logging for non-credential auth endpoints', () {
      for (final path in [
        ApiRoutes.searchUser,
        ApiRoutes.currentUser,
        ApiRoutes.verifyEmail,
      ]) {
        final options = RequestOptions(path: path);
        expect(
          shouldLogRequest(options, const FilterArgs(false, null)),
          isTrue,
          reason: '$path carries no credentials and must stay diagnosable',
        );
      }
    });

    test(
      'keeps logging for non-auth paths, including ones containing "auth"',
      () {
        for (final path in [
          '/journeys/active',
          '/users/me',
          '/journeys/1/author',
        ]) {
          final options = RequestOptions(path: path);
          expect(
            shouldLogRequest(options, const FilterArgs(false, null)),
            isTrue,
          );
        }
      },
    );
  });
}
