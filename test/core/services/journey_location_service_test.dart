import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tulink_flutter/core/services/journey_location_service.dart';
import 'package:tulink_flutter/core/services/location_service.dart';

void main() {
  Position position(double latitude, double longitude) => Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 8, 29),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  test('one native session feeds multiple independent consumers', () async {
    final source = _FakeLocationService();
    final service = JourneyLocationService(source);
    final first = <Position>[];
    final second = <Position>[];
    final firstSubscription = service.positions.listen(first.add);
    final secondSubscription = service.positions.listen(second.add);
    source.nextPosition = position(-1.2, 36.7);

    await service.start('journey-1');
    service.broadcastLatest();

    expect(source.streamRequests, 1);
    expect(first, hasLength(1));
    expect(second, hasLength(1));

    // Starting the same journey again reuses the native subscription.
    await service.start('journey-1');
    expect(source.streamRequests, 1);

    source.add(position(-1.21, 36.71));
    await Future<void>.delayed(Duration.zero);
    expect(first, hasLength(2));
    expect(second, hasLength(2));

    // A presentation consumer can detach without stopping native tracking.
    await firstSubscription.cancel();
    source.add(position(-1.22, 36.72));
    await Future<void>.delayed(Duration.zero);
    expect(first, hasLength(2));
    expect(second, hasLength(3));
    expect(source.nativeCancelCount, 0);

    await service.stop(journeyId: 'journey-1');
    expect(source.nativeCancelCount, 1);
    expect(service.isRunning, isFalse);

    await secondSubscription.cancel();
    await service.dispose();
    await source.dispose();
  });

  test('switching journeys cancels the previous native owner', () async {
    final source = _FakeLocationService()..nextPosition = position(-1.2, 36.7);
    final service = JourneyLocationService(source);

    await service.start('journey-1');
    await service.start('journey-2');

    expect(source.streamRequests, 2);
    expect(source.nativeCancelCount, 1);
    expect(service.journeyId, 'journey-2');

    // A stale owner cannot stop its replacement.
    await service.stop(journeyId: 'journey-1');
    expect(service.isRunning, isTrue);

    await service.dispose();
    await source.dispose();
  });

  test('a late fix cannot resurrect a stopped journey', () async {
    final source = _FakeLocationService();
    final service = JourneyLocationService(source);
    final gate = Completer<Position?>();
    source.positionGate = gate;

    final starting = service.start('journey-1');
    await Future<void>.delayed(Duration.zero);
    await service.stop(journeyId: 'journey-1');
    gate.complete(position(-1.2, 36.7));

    expect(await starting, isNull);
    expect(source.streamRequests, 0);
    expect(service.latestPosition, isNull);

    await service.dispose();
    await source.dispose();
  });

  test('a stale refresh cannot overwrite a replacement session', () async {
    final source = _FakeLocationService()..nextPosition = position(-1.2, 36.7);
    final service = JourneyLocationService(source);
    await service.start('journey-1');

    final oldRefresh = Completer<Position?>();
    source.positionGate = oldRefresh;
    final refreshing = service.refreshPosition(broadcast: true);
    await Future<void>.delayed(Duration.zero);

    await service.stop(journeyId: 'journey-1');
    source
      ..positionGate = null
      ..nextPosition = position(-1.3, 36.8);
    await service.start('journey-1');

    oldRefresh.complete(position(-1.1, 36.6));

    expect(await refreshing, isNull);
    expect(service.latestPosition?.latitude, -1.3);
    expect(service.latestPosition?.longitude, 36.8);

    await service.dispose();
    await source.dispose();
  });
}

class _FakeLocationService implements LocationService {
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  Position? nextPosition;
  Completer<Position?>? positionGate;
  int streamRequests = 0;
  int nativeCancelCount = 0;

  void add(Position position) => _controller.add(position);

  Future<void> dispose() => _controller.close();

  @override
  Future<Position?> getCurrentPosition({Duration? timeout}) async {
    final gate = positionGate;
    if (gate != null) return gate.future;
    return nextPosition;
  }

  @override
  Future<Position?> getLastKnownPosition() async => nextPosition;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamRequests++;
    return _controller.stream
        .transform(
          StreamTransformer<Position, Position>.fromHandlers(
            handleDone: (sink) => sink.close(),
          ),
        )
        .asBroadcastStream(onCancel: (_) => nativeCancelCount++);
  }
}
