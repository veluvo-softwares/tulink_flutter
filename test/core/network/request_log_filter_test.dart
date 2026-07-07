import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:tulink_flutter/core/network/request_log_filter.dart';

void main() {
  group('shouldLogRequest', () {
    test('suppresses request logging for /auth/login', () {
      final options = RequestOptions(path: '/auth/login');
      const args = FilterArgs(false, null);

      expect(shouldLogRequest(options, args), isFalse);
    });

    test('suppresses response logging for /auth/social', () {
      final options = RequestOptions(path: '/auth/social');
      const args = FilterArgs(true, {'idToken': 'fake.jwt.token'});

      expect(shouldLogRequest(options, args), isFalse);
    });

    test('suppresses error logging for /auth/refresh-token', () {
      final options = RequestOptions(path: '/auth/refresh-token');
      const args = FilterArgs(true, {'error': 'x'});

      expect(shouldLogRequest(options, args), isFalse);
    });

    test('keeps logging for non-auth request paths', () {
      final options = RequestOptions(path: '/journeys/active');
      const args = FilterArgs(false, null);

      expect(shouldLogRequest(options, args), isTrue);
    });

    test('keeps logging for non-auth response paths', () {
      final options = RequestOptions(path: '/users/me');
      const args = FilterArgs(true, {'name': 'x'});

      expect(shouldLogRequest(options, args), isTrue);
    });
  });
}
