import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';
import 'package:tulink_flutter/features/maps/presentation/services/convoy_interpolation_service.dart';

void main() {
  const nairobiLat = -1.2921;
  const nairobiLng = 36.8219;

  MemberPosition buildPosition({
    double? speed,
    double? heading,
    int timestamp = 0,
  }) {
    return MemberPosition(
      userId: 'peer-1',
      latitude: nairobiLat,
      longitude: nairobiLng,
      timestamp: timestamp,
      speed: speed,
      heading: heading,
      isMoving: (speed ?? 0) > 0,
    );
  }

  group('ConvoyInterpolationService', () {
    test('returns raw position when speed is null', () {
      final position = buildPosition(heading: 90);
      final result = ConvoyInterpolationService.interpolatedPosition(
        position,
        5000,
      );

      expect(result, <double>[nairobiLng, nairobiLat]);
    });

    test('returns raw position when speed is below the minimum threshold', () {
      final position = buildPosition(speed: 0.2, heading: 90);
      final result = ConvoyInterpolationService.interpolatedPosition(
        position,
        5000,
      );

      expect(result, <double>[nairobiLng, nairobiLat]);
    });

    test('returns raw position when heading is null', () {
      final position = buildPosition(speed: 10);
      final result = ConvoyInterpolationService.interpolatedPosition(
        position,
        5000,
      );

      expect(result, <double>[nairobiLng, nairobiLat]);
    });

    test('returns raw position when no time has elapsed', () {
      final position = buildPosition(speed: 10, heading: 90, timestamp: 5000);
      final result = ConvoyInterpolationService.interpolatedPosition(
        position,
        5000,
      );

      expect(result, <double>[nairobiLng, nairobiLat]);
    });

    test(
      'projects north (heading 0): latitude increases, longitude steady',
      () {
        // 10 m/s for 2 s = 20 m north.
        final position = buildPosition(speed: 10, heading: 0);
        final result = ConvoyInterpolationService.interpolatedPosition(
          position,
          2000,
        );

        expect(result[0], closeTo(nairobiLng, 1e-6)); // lng unchanged
        expect(result[1], greaterThan(nairobiLat)); // moved north
        expect(
          _metresBetween(nairobiLat, nairobiLng, result[1], result[0]),
          closeTo(20.0, 0.5),
        );
      },
    );

    test('projects east (heading 90): longitude up, latitude steady', () {
      final position = buildPosition(speed: 10, heading: 90);
      final result = ConvoyInterpolationService.interpolatedPosition(
        position,
        2000,
      );

      expect(result[1], closeTo(nairobiLat, 1e-6)); // lat ~unchanged
      expect(result[0], greaterThan(nairobiLng)); // moved east
      expect(
        _metresBetween(nairobiLat, nairobiLng, result[1], result[0]),
        closeTo(20.0, 0.5),
      );
    });

    test('clamps extrapolation to 6 s past the last fix', () {
      // 10 m/s; 60 s elapsed would be 600 m but must clamp to 6 s = 60 m.
      final position = buildPosition(speed: 10, heading: 0);
      final result = ConvoyInterpolationService.interpolatedPosition(
        position,
        60000,
      );

      final distance = _metresBetween(
        nairobiLat,
        nairobiLng,
        result[1],
        result[0],
      );
      expect(distance, closeTo(60.0, 1.0));
    });
  });
}

/// Great-circle distance in metres — test-side check independent of the
/// service's own projection math.
double _metresBetween(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMetres = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMetres * c;
}
