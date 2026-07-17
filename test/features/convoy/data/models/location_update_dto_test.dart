import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/models/location_update_dto.dart';

void main() {
  group('LocationUpdateDto.fromPosition', () {
    test('omits unknown negative heading and speed readings', () {
      final dto = LocationUpdateDto.fromPosition(
        journeyId: 'journey-1',
        latitude: -1.29,
        longitude: 36.82,
        timestamp: 123,
        heading: -1,
        speed: -1,
      );

      expect(dto.toJson(), isNot(contains('heading')));
      expect(dto.toJson(), isNot(contains('speed')));
    });

    test('keeps valid heading and speed readings', () {
      final dto = LocationUpdateDto.fromPosition(
        journeyId: 'journey-1',
        latitude: -1.29,
        longitude: 36.82,
        timestamp: 123,
        heading: 270,
        speed: 12.5,
      );

      expect(dto.toJson()['heading'], 270);
      expect(dto.toJson()['speed'], 12.5);
    });
  });
}
