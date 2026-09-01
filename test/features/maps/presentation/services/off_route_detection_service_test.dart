import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/presentation/services/off_route_detection_service.dart';

void main() {
  test(
    'reroutes immediately when the restored route is grossly stale',
    () async {
      var reroutes = 0;
      final detector = OffRouteDetectionService(
        onRerouteNeeded: () async => reroutes++,
      );

      await detector.processReading(deviationMetres: 150);

      expect(reroutes, 1);
    },
  );

  test('still filters a single moderate off-route GPS reading', () async {
    var reroutes = 0;
    final detector = OffRouteDetectionService(
      onRerouteNeeded: () async => reroutes++,
    );

    await detector.processReading(deviationMetres: 70);

    expect(reroutes, 0);
  });
}
