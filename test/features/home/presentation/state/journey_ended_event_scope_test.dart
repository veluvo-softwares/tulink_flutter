import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/state/journey_ended_event_scope.dart';

void main() {
  group('isJourneyEndedEventCurrent', () {
    test(
      'rejects a buffered completion from journey A after B is selected',
      () {
        expect(
          isJourneyEndedEventCurrent(
            eventJourneyId: 'journey-a',
            selectedJourneyId: 'journey-b',
            activeLayerJourneyId: 'journey-b',
          ),
          isFalse,
        );
      },
    );

    test('accepts the selected journey identity', () {
      expect(
        isJourneyEndedEventCurrent(
          eventJourneyId: 'journey-b',
          selectedJourneyId: 'journey-b',
          activeLayerJourneyId: 'journey-a',
        ),
        isTrue,
      );
    });

    test('falls back to the live layer identity while selection is empty', () {
      expect(
        isJourneyEndedEventCurrent(
          eventJourneyId: 'journey-a',
          selectedJourneyId: null,
          activeLayerJourneyId: 'journey-a',
        ),
        isTrue,
      );
    });
  });
}
