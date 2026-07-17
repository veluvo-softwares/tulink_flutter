import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/presentation/utils/route_rendering.dart';

void main() {
  group('buildRemainingRouteCoordinates', () {
    const route = <List<double>>[
      <double>[36.80, -1.28],
      <double>[36.81, -1.29],
      <double>[36.82, -1.30],
      <double>[36.83, -1.31],
    ];

    test('starts the visible line at the current snapped puck', () {
      final result = buildRemainingRouteCoordinates(
        routeCoordinates: route,
        segmentIndex: 1,
        snappedLongitude: 36.815,
        snappedLatitude: -1.295,
      );

      expect(result, <List<double>>[
        <double>[36.815, -1.295],
        <double>[36.82, -1.30],
        <double>[36.83, -1.31],
      ]);
    });

    test('clamps a stale segment index to the final valid segment', () {
      final result = buildRemainingRouteCoordinates(
        routeCoordinates: route,
        segmentIndex: 99,
        snappedLongitude: 36.825,
        snappedLatitude: -1.305,
      );

      expect(result, <List<double>>[
        <double>[36.825, -1.305],
        <double>[36.83, -1.31],
      ]);
    });

    test('returns no line for an incomplete route', () {
      final result = buildRemainingRouteCoordinates(
        routeCoordinates: const <List<double>>[
          <double>[36.80, -1.28],
        ],
        segmentIndex: 0,
        snappedLongitude: 36.80,
        snappedLatitude: -1.28,
      );

      expect(result, isEmpty);
    });
  });
}
