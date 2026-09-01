import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

void main() {
  Map<String, dynamic> baseJson() => <String, dynamic>{
    'id': 'j1',
    'name': 'Coast run',
    'leaderId': 'u1',
    'status': 'PENDING',
    'destination': {'latitude': -1.28, 'longitude': 36.82},
    'destinationAddress': 'Mombasa',
    'lagThresholdMeters': 500,
  };

  group('JourneyModel scheduling fields', () {
    test('parses scheduledFor and metadata.autoStart', () {
      final json = baseJson()
        ..['scheduledFor'] = '2026-07-19T06:30:00.000Z'
        ..['metadata'] = {'autoStart': true};

      final model = JourneyModel.fromJson(json);

      expect(model.scheduledFor, DateTime.parse('2026-07-19T06:30:00.000Z'));
      expect(model.autoStart, isTrue);
      expect(model.isScheduled, isTrue);
    });

    test('defaults to a start-now journey when absent', () {
      final model = JourneyModel.fromJson(baseJson());

      expect(model.scheduledFor, isNull);
      expect(model.autoStart, isFalse);
      expect(model.isScheduled, isFalse);
    });

    test('an ACTIVE journey is not "scheduled" even with a timestamp', () {
      final json = baseJson()
        ..['status'] = 'ACTIVE'
        ..['scheduledFor'] = '2026-07-19T06:30:00.000Z';

      final model = JourneyModel.fromJson(json);

      expect(model.status, JourneyStatus.ACTIVE);
      expect(model.isScheduled, isFalse);
    });
  });

  test('preserves a completed journey historical origin', () {
    final json = baseJson()
      ..['origin'] = {'latitude': -1.31, 'longitude': 36.79};

    final model = JourneyModel.fromJson(json);

    expect(model.origin, const LatLng(latitude: -1.31, longitude: 36.79));
    expect(model.toJson()['origin'], {'latitude': -1.31, 'longitude': 36.79});
  });
}
