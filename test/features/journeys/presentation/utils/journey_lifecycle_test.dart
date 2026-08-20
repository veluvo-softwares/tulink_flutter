import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/utils/journey_lifecycle.dart';

/// The home screen retires a composed draft on this rule. Before it existed,
/// finishing a journey and tapping Done left the spent draft on screen with
/// "Start journey" still enabled — and tapping it created a real duplicate
/// journey, because the backend's partial unique index only blocks a second
/// *open* journey and the previous one was already COMPLETED.
void main() {
  Journey journey(String id, JourneyStatus status) => Journey(
    id: id,
    name: 'Trip to Karen Shopping Centre',
    leaderId: 'leader-1',
    status: status,
    destination: const LatLng(latitude: -1.3234931, longitude: 36.7083102),
    destinationName: 'Karen Shopping Centre',
    destinationAddress: 'Nairobi, Kenya',
    lagThresholdMeters: 500,
  );

  test('a journey still held as current is not finished', () {
    expect(
      isJourneyFinished(
        journeyId: 'j1',
        currentJourney: journey('j1', JourneyStatus.ACTIVE),
        activeJourneys: const [],
      ),
      isFalse,
    );
  });

  test('a journey still listed as active is not finished', () {
    expect(
      isJourneyFinished(
        journeyId: 'j1',
        currentJourney: null,
        activeJourneys: [journey('j1', JourneyStatus.ACTIVE)],
      ),
      isFalse,
    );
  });

  test('a journey absent from both is finished', () {
    // endJourney() clears currentJourney and removes it from activeJourneys.
    expect(
      isJourneyFinished(
        journeyId: 'j1',
        currentJourney: null,
        activeJourneys: const [],
      ),
      isTrue,
    );
  });

  test('another journey being current does not keep this one alive', () {
    expect(
      isJourneyFinished(
        journeyId: 'j1',
        currentJourney: journey('j2', JourneyStatus.ACTIVE),
        activeJourneys: [journey('j2', JourneyStatus.ACTIVE)],
      ),
      isTrue,
    );
  });

  test('a pending journey the user has not started yet stays live', () {
    // Backing out of the map without starting must not wipe the draft.
    expect(
      isJourneyFinished(
        journeyId: 'j1',
        currentJourney: journey('j1', JourneyStatus.PENDING),
        activeJourneys: const [],
      ),
      isFalse,
    );
  });
}
