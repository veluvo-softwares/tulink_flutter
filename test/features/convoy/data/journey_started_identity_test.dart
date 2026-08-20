import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_websocket_data_source.dart';

/// `journey-started` identity must come from the payload, never from mutable
/// local state.
///
/// The gateway emits `{journey: {journeyId, journeyName, status}, timestamp}`
/// (see `location.gateway.ts#broadcastJourneyStarted` and
/// `journey.service.ts`). The client used to discard that and re-emit
/// `_currentJourneyId`, so an event still arriving from a room the user had
/// just left was reported as the room they had just joined.
void main() {
  group('identity is read from the real gateway payload', () {
    test('the nested shape the backend actually sends', () {
      expect(
        ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
          'journey': {
            'journeyId': 'journey-a',
            'journeyName': 'Trip to Ngong Hills',
            'status': 'ACTIVE',
          },
          'timestamp': 1786824664791,
        }),
        'journey-a',
      );
    });

    test('an id key is accepted as a fallback', () {
      expect(
        ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
          'journey': {'id': 'journey-a'},
        }),
        'journey-a',
      );
    });

    test('a flat payload is tolerated', () {
      expect(
        ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
          'journeyId': 'journey-a',
        }),
        'journey-a',
      );
    });
  });

  group(
    'unusable payloads are dropped, not attributed to the current room',
    () {
      test('no journey information at all', () {
        expect(
          ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
            'timestamp': 1,
          }),
          isNull,
          reason: 'substituting the local room id is what caused the bug',
        );
      });

      test('empty or blank id', () {
        expect(
          ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
            'journey': {'journeyId': '   '},
          }),
          isNull,
        );
      });

      test('wrongly typed payloads', () {
        expect(
          ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload(null),
          isNull,
        );
        expect(
          ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload(
            'journey-a',
          ),
          isNull,
        );
        expect(
          ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
            'journey': {'journeyId': 42},
          }),
          isNull,
        );
      });
    },
  );

  test('an event from another room is distinguishable', () {
    // The handler compares this against the room it currently owns and ignores
    // a mismatch; the value must therefore be the *event's* journey.
    final fromRoomA =
        ConvoyWebSocketDataSourceImpl.debugJourneyIdFromStartedPayload({
          'journey': {'journeyId': 'journey-a', 'status': 'ACTIVE'},
        });

    expect(fromRoomA, 'journey-a');
    expect(fromRoomA, isNot('journey-b'));
  });
}
