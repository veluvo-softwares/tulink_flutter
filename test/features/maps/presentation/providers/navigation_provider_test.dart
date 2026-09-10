import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/services/journey_location_service.dart';
import 'package:tulink_flutter/core/services/location_service.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/navigation_provider.dart';
import 'package:tulink_flutter/features/maps/presentation/services/voice_instruction_service.dart';

class _TestVoiceInstructionService extends VoiceInstructionService {
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('route cursor identity changes when the route origin changes', () {
    const first = RouteResultModel(
      coordinates: <List<double>>[
        <double>[36.80, -1.28],
        <double>[36.81, -1.29],
        <double>[36.82, -1.30],
      ],
      distanceMetres: 1000,
      durationSeconds: 300,
      steps: <RouteStepModel>[],
    );
    const recalculated = RouteResultModel(
      coordinates: <List<double>>[
        <double>[36.75, -1.25],
        <double>[36.81, -1.29],
        <double>[36.82, -1.30],
      ],
      distanceMetres: 1000,
      durationSeconds: 300,
      steps: <RouteStepModel>[],
    );

    expect(
      NavigationProvider.routeStorageIdentity(first),
      isNot(NavigationProvider.routeStorageIdentity(recalculated)),
    );
  });

  test('clears progress restored for the previous route when rerouting', () {
    final provider = NavigationProvider(
      journeyLocationService: JourneyLocationService(
        const GeolocatorLocationService(),
      ),
      voiceService: _TestVoiceInstructionService(),
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

  test('server voice preference can be applied without writing it back', () {
    bool? savedValue;
    final provider = NavigationProvider(
      journeyLocationService: JourneyLocationService(
        const GeolocatorLocationService(),
      ),
      voiceService: _TestVoiceInstructionService(),
      saveVoiceEnabled: (enabled) async => savedValue = enabled,
    );
    addTearDown(provider.dispose);

    provider.applyVoiceEnabled(enabled: false);

    expect(provider.isVoiceEnabled, isFalse);
    expect(savedValue, isNull);
  });
}
