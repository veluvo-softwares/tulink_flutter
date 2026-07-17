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

  group('interpolateRoutePosition', () {
    const rightAngleRoute = <List<double>>[
      <double>[0, 0],
      <double>[1, 0],
      <double>[1, 1],
    ];

    test('follows route vertices instead of cutting across a turn', () {
      final beforeCorner = interpolateRoutePosition(
        routeCoordinates: rightAngleRoute,
        startLongitude: 0.5,
        startLatitude: 0,
        startSegmentIndex: 0,
        targetLongitude: 1,
        targetLatitude: 0.5,
        targetSegmentIndex: 1,
        t: 0.25,
      );
      final afterCorner = interpolateRoutePosition(
        routeCoordinates: rightAngleRoute,
        startLongitude: 0.5,
        startLatitude: 0,
        startSegmentIndex: 0,
        targetLongitude: 1,
        targetLatitude: 0.5,
        targetSegmentIndex: 1,
        t: 0.75,
      );

      expect(beforeCorner.latitude, closeTo(0, 0.000001));
      expect(beforeCorner.longitude, closeTo(0.75, 0.000001));
      expect(beforeCorner.segmentIndex, 0);
      expect(afterCorner.longitude, closeTo(1, 0.000001));
      expect(afterCorner.latitude, closeTo(0.25, 0.000001));
      expect(afterCorner.segmentIndex, 1);
    });

    test('returns the exact target at completion', () {
      final result = interpolateRoutePosition(
        routeCoordinates: rightAngleRoute,
        startLongitude: 0.5,
        startLatitude: 0,
        startSegmentIndex: 0,
        targetLongitude: 1,
        targetLatitude: 0.5,
        targetSegmentIndex: 1,
        t: 1,
      );

      expect(result.longitude, 1);
      expect(result.latitude, 0.5);
      expect(result.segmentIndex, 1);
    });
  });
}
