import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_websocket_data_source.dart';

void main() {
  group('socket options', () {
    test('uses only the refresh-aware application reconnect loop', () {
      final options = buildConvoySocketOptions('firebase-token');

      expect(options['autoConnect'], isFalse);
      expect(options['reconnection'], isFalse);
      expect(options['forceNew'], isTrue);
      expect(options['transports'], equals(['websocket']));
      expect(options['auth'], equals({'token': 'firebase-token'}));
    });
  });

  group('SocketHandshakeError.fromEventPayload', () {
    test('parses the structured {code, message} map the backend sends', () {
      final error = SocketHandshakeError.fromEventPayload({
        'code': 'TOKEN_EXPIRED',
        'message': 'Token expired, please refresh',
      });

      expect(error.code, SocketAuthCode.tokenExpired);
      expect(error.message, 'Token expired, please refresh');
    });

    test('classifies TOKEN_REVOKED, AUTH_TEMPORARILY_UNAVAILABLE and '
        'AUTH_FAILED distinctly', () {
      expect(
        SocketHandshakeError.fromEventPayload({
          'code': 'TOKEN_REVOKED',
          'message': 'Token revoked, please sign in again',
        }).code,
        SocketAuthCode.tokenRevoked,
      );
      expect(
        SocketHandshakeError.fromEventPayload({
          'code': 'AUTH_TEMPORARILY_UNAVAILABLE',
          'message': 'Authentication service temporarily unavailable',
        }).code,
        SocketAuthCode.authTemporarilyUnavailable,
      );
      expect(
        SocketHandshakeError.fromEventPayload({
          'code': 'AUTH_FAILED',
          'message': 'Authentication failed',
        }).code,
        SocketAuthCode.authFailed,
      );
    });

    test('falls back to UNKNOWN for a payload with no code — e.g. a raw '
        'transport failure rather than a handshake rejection', () {
      final error = SocketHandshakeError.fromEventPayload(
        'ENOTFOUND api.example.com',
      );

      expect(error.code, SocketAuthCode.unknown);
      expect(error.message, 'ENOTFOUND api.example.com');
    });

    test('falls back to UNKNOWN for a map with no code field', () {
      final error = SocketHandshakeError.fromEventPayload({
        'message': 'Not a participant of this journey',
      });

      expect(error.code, SocketAuthCode.unknown);
      expect(error.message, 'Not a participant of this journey');
    });
  });

  group('disconnect recovery classification', () {
    test('reconnects after a server heartbeat timeout', () {
      expect(
        shouldReconnectAfterDisconnect(
          'io server disconnect',
          heartbeatTimedOut: true,
        ),
        isTrue,
      );
    });

    test('does not reconnect after a logout server disconnect', () {
      expect(
        shouldReconnectAfterDisconnect(
          'io server disconnect',
          heartbeatTimedOut: false,
        ),
        isFalse,
      );
    });

    test('reconnects after a transport failure', () {
      expect(
        shouldReconnectAfterDisconnect(
          'transport close',
          heartbeatTimedOut: false,
        ),
        isTrue,
      );
    });
  });
}
