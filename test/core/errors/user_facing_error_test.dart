import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/errors/user_facing_error.dart';

void main() {
  group('userFacingErrorMessage', () {
    test('uses concise copy for typed network failures', () {
      expect(
        userFacingErrorMessage(NetworkFailure.noInternet),
        networkErrorMessage,
      );
    });

    test('recognises wrapped low-level network errors', () {
      const failure = ServerFailure(
        message: 'SocketException: No route to host',
      );
      expect(userFacingErrorMessage(failure), networkErrorMessage);
    });

    test('hides non-network implementation details', () {
      const failure = ServerFailure(
        message: 'type Map<dynamic, dynamic> is not a subtype',
        details: 'internal stack details',
      );
      expect(userFacingErrorMessage(failure), genericErrorMessage);
    });
  });
}
