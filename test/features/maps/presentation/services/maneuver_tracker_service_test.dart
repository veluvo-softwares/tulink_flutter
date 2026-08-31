import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';
import 'package:tulink_flutter/features/maps/presentation/services/maneuver_tracker_service.dart';

void main() {
  RouteResultModel route() => RouteResultModel(
    coordinates: const [
      [36.800000, -1.300000],
      [36.800000, -1.290000],
      [36.800000, -1.280000],
    ],
    distanceMetres: 2224,
    durationSeconds: 240,
    steps: const [
      RouteStepModel(
        instruction: 'Continue north',
        maneuver: 'straight',
        distanceMetres: 2224,
      ),
    ],
  );

  test('progress advances within a long polyline segment', () {
    final tracker = ManeuverTrackerService()..loadRoute(route());

    final atStart = tracker.update(
      snappedLatitude: -1.300000,
      snappedLongitude: 36.800000,
      segmentIndex: 0,
    );
    final halfway = tracker.update(
      snappedLatitude: -1.295000,
      snappedLongitude: 36.800000,
      segmentIndex: 0,
    );

    expect(
      halfway.distanceRemainingMetres,
      lessThan(atStart.distanceRemainingMetres - 500),
    );
  });

  test('within-segment progress is clamped to the matched segment', () {
    final tracker = ManeuverTrackerService()..loadRoute(route());

    final progress = tracker.update(
      snappedLatitude: -1.270000,
      snappedLongitude: 36.800000,
      segmentIndex: 0,
    );

    expect(progress.distanceRemainingMetres, greaterThan(1000));
  });
}
