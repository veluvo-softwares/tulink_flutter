import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';

void main() {
  group('Failure Classes Tests', () {
    group('ServerFailure', () {
      test('should create correct failure from status codes', () {
        final failure400 = ServerFailure.fromStatusCode(400);
        expect(failure400.statusCode, equals(400));
        expect(failure400.message, contains('Bad request'));

        final failure401 = ServerFailure.fromStatusCode(401);
        expect(failure401.statusCode, equals(401));
        expect(failure401.message, contains('Authentication failed'));

        final failure404 = ServerFailure.fromStatusCode(404);
        expect(failure404.statusCode, equals(404));
        expect(failure404.message, contains('not found'));

        final failure500 = ServerFailure.fromStatusCode(500);
        expect(failure500.statusCode, equals(500));
        expect(failure500.message, contains('Internal server error'));
      });

      test('should handle unknown status codes', () {
        final failure = ServerFailure.fromStatusCode(999);
        expect(failure.statusCode, equals(999));
        expect(failure.message, contains('Status code: 999'));
      });

      test('should copy with new values', () {
        final original = ServerFailure.fromStatusCode(500);
        final copied = original.copyWith(
          message: 'Custom message',
          details: 'Custom details',
        );

        expect(copied.message, equals('Custom message'));
        expect(copied.details, equals('Custom details'));
        expect(copied.statusCode, equals(original.statusCode));
        expect(copied.timestamp, equals(original.timestamp));
      });

      test('should have timestamp set', () {
        final failure = ServerFailure.fromStatusCode(400);
        expect(failure.timestamp, isNotNull);
        expect(failure.timestamp!.isBefore(DateTime.now().add(Duration(seconds: 1))), isTrue);
      });
    });

    group('AuthFailure', () {
      test('should have correct predefined auth failures', () {
        expect(AuthFailure.invalidCredentials.isRetryable, isTrue);
        expect(AuthFailure.invalidCredentials.requiresReauth, isFalse);
        expect(AuthFailure.invalidCredentials.statusCode, equals(401));

        expect(AuthFailure.tokenExpired.requiresReauth, isTrue);
        expect(AuthFailure.tokenExpired.statusCode, equals(401));

        expect(AuthFailure.accessDenied.statusCode, equals(403));
        expect(AuthFailure.accessDenied.isRetryable, isFalse);

        expect(AuthFailure.accountLocked.isRetryable, isTrue);
        expect(AuthFailure.accountLocked.statusCode, equals(423));

        expect(AuthFailure.emailNotVerified.isRetryable, isTrue);
        expect(AuthFailure.userAlreadyExists.statusCode, equals(409));
      });

      test('should copy with preserved flags', () {
        final original = AuthFailure.invalidCredentials;
        final copied = original.copyWith(message: 'New message');

        expect(copied.message, equals('New message'));
        expect(copied.isRetryable, equals(original.isRetryable));
        expect(copied.requiresReauth, equals(original.requiresReauth));
      });
    });

    group('ValidationFailure', () {
      test('should create field-specific errors', () {
        final fieldErrors = {
          'email': 'Invalid email format',
          'password': 'Password too short',
        };

        final failure = ValidationFailure.withFieldErrors(
          message: 'Form validation failed',
          fieldErrors: fieldErrors,
        );

        expect(failure.fieldErrors, equals(fieldErrors));
        expect(failure.message, equals('Form validation failed'));
        expect(failure.details, isNotNull);
      });

      test('should have predefined validation failures', () {
        expect(ValidationFailure.invalidEmail.message, contains('valid email'));
        expect(ValidationFailure.invalidPassword.message, contains('8 characters'));
        expect(ValidationFailure.weakPassword.message, contains('too weak'));
        expect(ValidationFailure.passwordMismatch.message, contains('do not match'));
        expect(ValidationFailure.invalidName.message, contains('valid name'));
        expect(ValidationFailure.requiredField.message, contains('required'));
      });
    });

    group('NetworkFailure', () {
      test('should have predefined network failures', () {
        expect(NetworkFailure.noInternet.message, contains('No internet'));
        expect(NetworkFailure.timeout.message, contains('timeout'));
        expect(NetworkFailure.connectionError.message, contains('Connection error'));
        expect(NetworkFailure.unknown.message, contains('Network error'));
      });

      test('should copy correctly', () {
        final original = NetworkFailure.noInternet;
        final copied = original.copyWith(
          details: 'Custom network details',
        );

        expect(copied.message, equals(original.message));
        expect(copied.details, equals('Custom network details'));
      });
    });

    group('CacheFailure', () {
      test('should have predefined cache failures', () {
        expect(CacheFailure.read.message, contains('read'));
        expect(CacheFailure.write.message, contains('write'));
        expect(CacheFailure.delete.message, contains('delete'));
        expect(CacheFailure.corrupted.message, contains('corrupted'));
      });
    });

    group('TokenFailure', () {
      test('should have predefined token failures', () {
        expect(TokenFailure.accessTokenExpired.tokenType, equals('access'));
        expect(TokenFailure.refreshTokenExpired.tokenType, equals('refresh'));
        expect(TokenFailure.tokenCorrupted.message, contains('corrupted'));
        expect(TokenFailure.tokenMissing.message, contains('not found'));
      });

      test('should copy with token type preserved', () {
        final original = TokenFailure.accessTokenExpired;
        final copied = original.copyWith(message: 'New message');

        expect(copied.message, equals('New message'));
        expect(copied.tokenType, equals(original.tokenType));
      });
    });

    group('Failure Equality', () {
      test('should be equal when properties match', () {
        final failure1 = ServerFailure(
          message: 'Test message',
          statusCode: 500,
          details: 'Test details',
          timestamp: DateTime(2024, 1, 1),
        );

        final failure2 = ServerFailure(
          message: 'Test message',
          statusCode: 500,
          details: 'Test details',
          timestamp: DateTime(2024, 1, 1),
        );

        expect(failure1, equals(failure2));
        expect(failure1.hashCode, equals(failure2.hashCode));
      });

      test('should not be equal when properties differ', () {
        final failure1 = ServerFailure.fromStatusCode(500);
        final failure2 = ServerFailure.fromStatusCode(404);

        expect(failure1, isNot(equals(failure2)));
      });
    });

    group('Failure Props', () {
      test('should include all relevant properties in props', () {
        final failure = ServerFailure(
          message: 'Test',
          statusCode: 500,
          details: 'Details',
          timestamp: DateTime(2024, 1, 1),
        );

        final props = failure.props;
        expect(props, contains('Test'));
        expect(props, contains(500));
        expect(props, contains('Details'));
        expect(props, contains(DateTime(2024, 1, 1)));
      });
    });

    group('Edge Cases', () {
      test('should handle null values in copy operations', () {
        final original = ServerFailure.fromStatusCode(500);
        final copied = original.copyWith();

        expect(copied.message, equals(original.message));
        expect(copied.statusCode, equals(original.statusCode));
        expect(copied.details, equals(original.details));
        expect(copied.timestamp, equals(original.timestamp));
      });

      test('should handle empty field errors map', () {
        final failure = ValidationFailure.withFieldErrors(
          message: 'Test',
          fieldErrors: {},
        );

        expect(failure.fieldErrors, isEmpty);
      });

      test('should create failures with minimal data', () {
        final serverFailure = ServerFailure(message: 'Minimal');
        expect(serverFailure.message, equals('Minimal'));
        expect(serverFailure.statusCode, isNull);
        expect(serverFailure.details, isNull);

        final authFailure = AuthFailure(message: 'Auth minimal');
        expect(authFailure.message, equals('Auth minimal'));
        expect(authFailure.isRetryable, isFalse);
        expect(authFailure.requiresReauth, isFalse);
      });
    });

    group('Failure Inheritance', () {
      test('should properly extend base Failure class', () {
        final serverFailure = ServerFailure.fromStatusCode(500);
        final authFailure = AuthFailure.invalidCredentials;
        final validationFailure = ValidationFailure.invalidEmail;
        final networkFailure = NetworkFailure.noInternet;
        final cacheFailure = CacheFailure.read;
        final tokenFailure = TokenFailure.accessTokenExpired;

        expect(serverFailure, isA<Failure>());
        expect(authFailure, isA<Failure>());
        expect(validationFailure, isA<Failure>());
        expect(networkFailure, isA<Failure>());
        expect(cacheFailure, isA<Failure>());
        expect(tokenFailure, isA<Failure>());
      });
    });
  });
}