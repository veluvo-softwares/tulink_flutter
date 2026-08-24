import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

/// Guards the destination-presentation contract.
///
/// The live bug this covers: Google Places returns a coarse `formattedAddress`
/// ("Nairobi, Kenya") for POIs whose `displayName` is specific ("Karen Shopping
/// Centre"). Storing only the address made every journey render as the city.
void main() {
  Journey buildJourney({
    String? destinationName,
    String destinationAddress = '',
  }) {
    return Journey(
      id: 'j1',
      name: 'Trip to Karen Shopping Centre',
      leaderId: 'leader-1',
      status: JourneyStatus.COMPLETED,
      destination: const LatLng(latitude: -1.3234931, longitude: 36.7083102),
      destinationName: destinationName,
      destinationAddress: destinationAddress,
      lagThresholdMeters: 500,
    );
  }

  group('Journey.destinationLabel', () {
    test('prefers the place name over the coarse formatted address', () {
      final journey = buildJourney(
        destinationName: 'Karen Shopping Centre',
        destinationAddress: 'Nairobi, Kenya',
      );

      expect(journey.destinationLabel, 'Karen Shopping Centre');
    });

    test('falls back to the address for journeys created before the field', () {
      // Legacy row: destination_name is NULL in the database.
      final legacy = buildJourney(destinationAddress: 'Nairobi, Kenya');

      expect(legacy.destinationName, isNull);
      expect(legacy.destinationLabel, 'Nairobi, Kenya');
    });

    test('falls back when the backend sends an empty or blank name', () {
      expect(
        buildJourney(
          destinationName: '',
          destinationAddress: 'Nairobi, Kenya',
        ).destinationLabel,
        'Nairobi, Kenya',
      );
      expect(
        buildJourney(
          destinationName: '   ',
          destinationAddress: 'Nairobi, Kenya',
        ).destinationLabel,
        'Nairobi, Kenya',
      );
    });

    test('trims surrounding whitespace from the place name', () {
      expect(
        buildJourney(
          destinationName: '  Karen Shopping Centre  ',
          destinationAddress: 'Nairobi, Kenya',
        ).destinationLabel,
        'Karen Shopping Centre',
      );
    });
  });

  group('Journey.destinationSubtitle', () {
    test('keeps the address available as secondary information', () {
      final journey = buildJourney(
        destinationName: 'Karen Shopping Centre',
        destinationAddress: 'Nairobi, Kenya',
      );

      expect(journey.destinationSubtitle, 'Nairobi, Kenya');
    });

    test('is null when it would merely repeat the label', () {
      // Legacy journeys: label and address are the same string.
      final legacy = buildJourney(destinationAddress: 'Nairobi, Kenya');

      expect(legacy.destinationSubtitle, isNull);
    });

    test('is null when there is no address at all', () {
      expect(
        buildJourney(
          destinationName: 'Karen Shopping Centre',
        ).destinationSubtitle,
        isNull,
      );
    });
  });

  test('destinationName participates in value equality', () {
    final karen = buildJourney(
      destinationName: 'Karen Shopping Centre',
      destinationAddress: 'Nairobi, Kenya',
    );
    final hub = buildJourney(
      destinationName: 'The Hub Karen',
      destinationAddress: 'Nairobi, Kenya',
    );

    expect(karen, isNot(equals(hub)));
    expect(
      karen,
      equals(
        buildJourney(
          destinationName: 'Karen Shopping Centre',
          destinationAddress: 'Nairobi, Kenya',
        ),
      ),
    );
  });
}
