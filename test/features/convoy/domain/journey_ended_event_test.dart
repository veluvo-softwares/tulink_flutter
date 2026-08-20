import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/journey_ended_event.dart';

/// Completing a journey marks every participant `LEFT`, so `GET /journeys/{id}`
/// answers 403 to the people who were on it. The finished journey therefore has
/// to come from the event payload — discarding it made the completion summary
/// unreachable after any server-driven end.
void main() {
  group('identity comes from the payload', () {
    test('reads the journey id the gateway sends', () {
      expect(
        JourneyEndedEvent.journeyIdFrom({
          'journey': {'id': 'journey-a', 'status': 'COMPLETED'},
          'reason': 'completed',
        }),
        'journey-a',
      );
    });

    test('tolerates a journeyId key and a flat shape', () {
      expect(
        JourneyEndedEvent.journeyIdFrom({
          'journey': {'journeyId': 'journey-a'},
        }),
        'journey-a',
      );
      expect(
        JourneyEndedEvent.journeyIdFrom({'journeyId': 'journey-a'}),
        'journey-a',
      );
    });

    test('returns null for unusable payloads', () {
      expect(JourneyEndedEvent.journeyIdFrom(null), isNull);
      expect(JourneyEndedEvent.journeyIdFrom({'reason': 'completed'}), isNull);
      expect(
        JourneyEndedEvent.journeyIdFrom({
          'journey': {'id': '  '},
        }),
        isNull,
      );
    });
  });

  group('the finished journey is carried on the event', () {
    test('the payload journey is retained for the summary', () {
      final event = JourneyEndedEvent.fromJson('journey-a', {
        'journey': {
          'id': 'journey-a',
          'name': 'Trip to Ngong Hills',
          'status': 'COMPLETED',
        },
        'reason': 'completed',
        'endedAt': '2026-08-16T08:55:00.000Z',
      });

      expect(
        event.journey,
        isNotNull,
        reason: 'without this the summary can never be built',
      );
      expect(event.journey!['id'], 'journey-a');
      expect(event.reason, 'completed');
      expect(event.endedAt, isNotNull);
    });

    test('a payload with no journey is survivable', () {
      final event = JourneyEndedEvent.fromJson('journey-a', {
        'reason': 'cancelled',
      });

      expect(event.journey, isNull);
      expect(event.journeyId, 'journey-a');
    });
  });
}
