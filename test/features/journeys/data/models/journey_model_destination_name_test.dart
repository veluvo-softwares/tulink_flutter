import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';

/// Wire-format contract for `destinationName`, including compatibility with
/// journeys created before the column existed.
void main() {
  Map<String, dynamic> baseJson() => <String, dynamic>{
    'id': 'j1',
    'name': 'Trip to Karen Shopping Centre',
    'leaderId': 'leader-1',
    'status': 'ACTIVE',
    'destination': {'latitude': -1.3234931, 'longitude': 36.7083102},
    'destinationAddress': 'Nairobi, Kenya',
    'lagThresholdMeters': 500,
  };

  group('JourneyModel.fromJson', () {
    test('parses destinationName when the backend sends it', () {
      final model = JourneyModel.fromJson(
        baseJson()..['destinationName'] = 'Karen Shopping Centre',
      );

      expect(model.destinationName, 'Karen Shopping Centre');
      expect(model.destinationAddress, 'Nairobi, Kenya');
      expect(model.destinationLabel, 'Karen Shopping Centre');
    });

    test('leaves destinationName null when the field is absent', () {
      final model = JourneyModel.fromJson(baseJson());

      expect(model.destinationName, isNull);
      // Backward compatibility: display still resolves to something useful.
      expect(model.destinationLabel, 'Nairobi, Kenya');
    });

    test(
      'leaves destinationName null when the backend sends explicit null',
      () {
        final model = JourneyModel.fromJson(
          baseJson()..['destinationName'] = null,
        );

        expect(model.destinationName, isNull);
        expect(model.destinationLabel, 'Nairobi, Kenya');
      },
    );

    test('does not disturb destination coordinates', () {
      final model = JourneyModel.fromJson(
        baseJson()..['destinationName'] = 'Karen Shopping Centre',
      );

      // Latitude/longitude must survive verbatim — no swap, no truncation.
      expect(model.destination.latitude, -1.3234931);
      expect(model.destination.longitude, 36.7083102);
    });
  });

  group('JourneyModel.toJson', () {
    test('round-trips destinationName', () {
      final model = JourneyModel.fromJson(
        baseJson()..['destinationName'] = 'Karen Shopping Centre',
      );

      expect(model.toJson()['destinationName'], 'Karen Shopping Centre');
    });

    test('omits destinationName entirely when unknown', () {
      final model = JourneyModel.fromJson(baseJson());

      // Omitted rather than serialised as null/"", so a cached legacy journey
      // cannot later be written back as an empty name.
      expect(model.toJson().containsKey('destinationName'), isFalse);
    });
  });
}
