import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/services/journey_location_service.dart';
import 'package:tulink_flutter/core/services/location_service.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/navigation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clears progress restored for the previous route when rerouting', () {
    final provider = NavigationProvider(
      journeyLocationService: JourneyLocationService(
        const GeolocatorLocationService(),
      ),
    );
    addTearDown(provider.dispose);

    provider.setRestoredSegmentIndexForTesting(42);

    provider.loadRoute(
      const RouteResultModel(
        coordinates: <List<double>>[
          <double>[36.80, -1.28],
          <double>[36.81, -1.29],
          <double>[36.82, -1.30],
        ],
        distanceMetres: 1000,
        durationSeconds: 300,
        steps: <RouteStepModel>[],
      ),
    );

    expect(provider.restoredSegmentIndexForTesting, isNull);
    expect(provider.currentProgress, isNull);
    expect(provider.lastKnownProgress, isNull);
  });
}
