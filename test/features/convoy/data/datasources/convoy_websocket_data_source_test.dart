import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_websocket_data_source.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/route_updated_event.dart';

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

  group('resumable join recovery', () {
    test('parses an inline delta from the joined-journey acknowledgement', () {
      final recovery = JoinRecoveryEnvelope.fromAcknowledgement({
        'journeyId': 'journey-1',
        'recovery': {
          'mode': 'DELTA',
          'updates': [
            {'sequenceNumber': 42},
          ],
          'nextSequence': 42,
          'hasMore': false,
        },
      });

      expect(recovery?.mode, 'DELTA');
      expect(recovery?.updates, hasLength(1));
      expect(recovery?.nextSequence, 42);
      expect(recovery?.hasMore, isFalse);
    });

    test('recognizes snapshot repair and rejects malformed envelopes', () {
      expect(
        JoinRecoveryEnvelope.fromAcknowledgement({
          'recovery': {'mode': 'SNAPSHOT_REQUIRED', 'reason': 'CURSOR_TOO_OLD'},
        })?.mode,
        'SNAPSHOT_REQUIRED',
      );
      expect(
        JoinRecoveryEnvelope.fromAcknowledgement({
          'recovery': {'mode': 'UNKNOWN'},
        }),
        isNull,
      );
      expect(JoinRecoveryEnvelope.fromAcknowledgement({}), isNull);
    });
  });

  group('canonical route update payload', () {
    test('parses a versioned journey event', () {
      final event = RouteUpdatedEvent.fromPayload({
        'journeyId': 'journey-1',
        'routeVersion': 4,
        'reason': 'LEADER_REROUTE',
        'updatedAt': '2026-08-30T10:00:00.000Z',
      });

      expect(event?.journeyId, 'journey-1');
      expect(event?.routeVersion, 4);
      expect(event?.reason, 'LEADER_REROUTE');
    });

    test('drops malformed or identity-free events', () {
      expect(RouteUpdatedEvent.fromPayload({'routeVersion': 2}), isNull);
      expect(RouteUpdatedEvent.fromPayload({'journeyId': 'A'}), isNull);
      expect(
        RouteUpdatedEvent.fromPayload({'journeyId': 'A', 'routeVersion': 2.5}),
        isNull,
      );
      expect(
        RouteUpdatedEvent.fromPayload({
          'journeyId': 'A',
          'routeVersion': double.infinity,
        }),
        isNull,
      );
    });

    test('uses value equality for valid integral route versions', () {
      final first = RouteUpdatedEvent.fromPayload({
        'journeyId': 'journey-1',
        'routeVersion': 4.0,
        'reason': 'LEADER_REROUTE',
        'updatedAt': '2026-08-30T10:00:00.000Z',
      });
      final second = RouteUpdatedEvent.fromPayload({
        'journeyId': 'journey-1',
        'routeVersion': 4,
        'reason': 'LEADER_REROUTE',
        'updatedAt': '2026-08-30T10:00:00.000Z',
      });

      expect(first, second);
    });
  });
}
