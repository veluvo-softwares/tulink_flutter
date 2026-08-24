import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/location_publish_ack.dart';

/// The `location-update-ack` contract, pinned against the shapes the backend
/// gateway actually emits.
///
/// The client used to read `accepted` only to print it and then completed the
/// publish as success regardless, so a rejection removed the point from the
/// offline outbox and skipped the REST fallback — silent data loss.
///
/// Reason codes, from `apps/api/src/modules/location/location.gateway.ts`:
///
/// * success acks carry **no** `accepted` field and a `strategy` of
///   `REALTIME` / `BATCHED` / `POLLING`;
/// * `accepted: false, reason: THROTTLED_OR_DUPLICATE` — the server either
///   already has the point (2 s dedup key, `NX`) or intentionally suppressed
///   it (`PriorityService.shouldThrottle`);
/// * `accepted: false, reason: SERVER_ERROR` — the gateway's catch block ran
///   before persistence, so the server does **not** have the point;
/// * `accepted: false` with a terminal reason — membership, journey status or
///   payload validation; retrying cannot succeed.
void main() {
  group('acceptance', () {
    test('an ack with no accepted field is an acceptance', () {
      for (final strategy in ['REALTIME', 'BATCHED', 'POLLING']) {
        final ack = LocationPublishAck.fromPayload({
          'clientPointId': 'p1',
          'sequenceNumber': 7,
          'strategy': strategy,
        });
        expect(ack.outcome, LocationAckOutcome.accepted, reason: strategy);
        expect(ack.isDelivered, isTrue);
        expect(ack.sequenceNumber, 7);
      }
    });

    test('accepted: true is an acceptance', () {
      final ack = LocationPublishAck.fromPayload({
        'clientPointId': 'p1',
        'accepted': true,
      });
      expect(ack.outcome, LocationAckOutcome.accepted);
    });
  });

  group('suppression is delivery, and is documented as such', () {
    test('THROTTLED_OR_DUPLICATE counts as delivered', () {
      final ack = LocationPublishAck.fromPayload({
        'clientPointId': 'p1',
        'accepted': false,
        'reason': 'THROTTLED_OR_DUPLICATE',
      });
      expect(ack.outcome, LocationAckOutcome.suppressed);
      expect(
        ack.isDelivered,
        isTrue,
        reason: 'the server has the point, or chose to drop it',
      );
      expect(ack.isRetryable, isFalse);
    });

    test('the delivered-by-suppression set is exactly one documented code', () {
      // Widening this set silently converts data loss into "success", so the
      // membership is asserted rather than left implicit.
      expect(LocationPublishAck.suppressedReasons, {'THROTTLED_OR_DUPLICATE'});
    });
  });

  group('rejection is never success', () {
    test('SERVER_ERROR is retryable and not delivered', () {
      final ack = LocationPublishAck.fromPayload({
        'clientPointId': 'p1',
        'accepted': false,
        'reason': 'SERVER_ERROR',
      });
      expect(ack.outcome, LocationAckOutcome.retryable);
      expect(ack.isDelivered, isFalse);
      expect(ack.isRetryable, isTrue);
    });

    test('an unrecognised rejection reason is retryable, never delivered', () {
      final ack = LocationPublishAck.fromPayload({
        'accepted': false,
        'reason': 'SOMETHING_NEW',
      });
      expect(ack.outcome, LocationAckOutcome.retryable);
      expect(
        ack.isDelivered,
        isFalse,
        reason: 'delivery must never be assumed from an unknown code',
      );
    });

    test('a rejection with no reason at all is retryable', () {
      final ack = LocationPublishAck.fromPayload({'accepted': false});
      expect(ack.outcome, LocationAckOutcome.retryable);
      expect(ack.reason, 'UNKNOWN');
    });

    test('terminal reasons are terminal, not retried forever', () {
      for (final reason in LocationPublishAck.terminalReasons) {
        final ack = LocationPublishAck.fromPayload({
          'accepted': false,
          'reason': reason,
        });
        expect(ack.outcome, LocationAckOutcome.terminal, reason: reason);
        expect(ack.isDelivered, isFalse);
        expect(ack.isRetryable, isFalse);
      }
    });
  });

  group('missing and malformed answers', () {
    test('a timeout is a retryable failure, not a delivery', () {
      expect(LocationPublishAck.timedOut.outcome, LocationAckOutcome.retryable);
      expect(LocationPublishAck.timedOut.isDelivered, isFalse);
      expect(LocationPublishAck.timedOut.reason, 'ACK_TIMEOUT');
    });

    test('an uncorrelatable answer is a failure', () {
      expect(
        LocationPublishAck.malformed.outcome,
        LocationAckOutcome.retryable,
      );
      expect(LocationPublishAck.malformed.isDelivered, isFalse);
    });
  });
}
