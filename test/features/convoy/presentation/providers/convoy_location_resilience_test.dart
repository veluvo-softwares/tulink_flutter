import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/services/location_permission_service.dart';
import 'package:tulink_flutter/core/services/location_service.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/journey_ended_event.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/participant_arrived_event.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';

import 'convoy_provider_test.mocks.dart';

/// Regression suite for the live-convoy deadlock.
///
/// Before the fix, `Geolocator.getCurrentPosition()` was awaited without a
/// timeout on the coordination-start path. On a device that cannot produce a
/// fix the future never completed *and never threw*, so the room was never
/// joined and the UI showed "CONNECTING..." forever. These tests pin the
/// invariant that location and convoy membership fail independently.
void main() {
  late MockStreamConvoyPositions streamConvoyPositions;
  late MockPublishMyPosition publishMyPosition;
  late MockFetchLatestSnapshot fetchLatestSnapshot;
  late MockConvoyRepository repository;
  late _FakeLocationService location;
  late _FakePermissionGate permission;
  late StreamController<Position> positionController;

  const journeyId = 'journey-1';
  const otherJourneyId = 'journey-2';

  Position position({double lat = -1.2921, double lng = 36.8219}) => Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 8, 14),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  ConvoyProvider buildProvider() => ConvoyProvider(
    streamConvoyPositions: streamConvoyPositions,
    publishMyPosition: publishMyPosition,
    fetchLatestSnapshot: fetchLatestSnapshot,
    repository: repository,
    locationService: location,
    permissionGate: permission,
  );

  setUp(() {
    streamConvoyPositions = MockStreamConvoyPositions();
    publishMyPosition = MockPublishMyPosition();
    fetchLatestSnapshot = MockFetchLatestSnapshot();
    repository = MockConvoyRepository();
    positionController = StreamController<Position>.broadcast();
    location = _FakeLocationService(positionController.stream);
    permission = _FakePermissionGate();

    when(streamConvoyPositions(any)).thenAnswer(
      (_) =>
          const Stream<({ConvoySnapshot? snapshot, Failure? failure})>.empty(),
    );
    when(
      repository.connectionStateStream,
    ).thenAnswer((_) => const Stream<ConvoyConnectionState>.empty());
    when(
      repository.journeyEndedStream,
    ).thenAnswer((_) => const Stream<JourneyEndedEvent>.empty());
    when(
      repository.participantArrivedStream,
    ).thenAnswer((_) => const Stream<ParticipantArrivedEvent>.empty());
    when(
      repository.journeyStartedStream,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(
      repository.participantAcceptedStream,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(
      publishMyPosition(
        journeyId: anyNamed('journeyId'),
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
        timestamp: anyNamed('timestamp'),
        accuracy: anyNamed('accuracy'),
        altitude: anyNamed('altitude'),
        heading: anyNamed('heading'),
        speed: anyNamed('speed'),
        batteryLevel: anyNamed('batteryLevel'),
        isMoving: anyNamed('isMoving'),
      ),
    ).thenAnswer((_) async => (success: true, failure: null));
  });

  tearDown(() async {
    await positionController.close();
  });

  group('convoy membership does not depend on a location fix', () {
    test(
      'startCoordination subscribes to the room even when no fix is available',
      () async {
        location.hangs = true;
        final provider = buildProvider();

        // Must complete: the whole defect was that this never returned.
        await provider
            .startCoordination(journeyId)
            .timeout(const Duration(seconds: 5));

        expect(
          provider.isSubscribed,
          isTrue,
          reason: 'room membership must not sit behind GPS acquisition',
        );
        expect(provider.currentJourneyId, journeyId);
        verify(streamConvoyPositions(journeyId)).called(1);
      },
    );

    test(
      'location trouble is reported separately from convoy errors',
      () async {
        location.hangs = true;
        final provider = buildProvider();

        await provider
            .startCoordination(journeyId)
            .timeout(const Duration(seconds: 5));

        // The status bar keys off these two independently; conflating them is
        // what made the UI claim the socket was still connecting.
        expect(provider.locationFailure, isNotNull);
        expect(provider.isSubscribed, isTrue);
      },
    );
  });

  group('retrying location without recreating the journey', () {
    test('a later fix clears the failure and starts publishing', () async {
      location.hangs = true;
      final provider = buildProvider();
      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));
      expect(provider.locationFailure, isNotNull);

      // The device finally gets a fix.
      location
        ..hangs = false
        ..nextPosition = position();

      final recovered = await provider.retryLocationPublishing();

      expect(recovered, isTrue);
      expect(provider.locationFailure, isNull);
      expect(provider.isPublishing, isTrue);
      // Same journey throughout — no teardown/recreate.
      expect(provider.currentJourneyId, journeyId);
    });

    test(
      'retry reports failure honestly while the fix is still missing',
      () async {
        location.hangs = true;
        final provider = buildProvider();
        await provider
            .startCoordination(journeyId)
            .timeout(const Duration(seconds: 5));

        final recovered = await provider.retryLocationPublishing();

        expect(recovered, isFalse);
        expect(provider.locationFailure, isNotNull);
      },
    );

    test('retry is a no-op when no journey is being coordinated', () async {
      final provider = buildProvider();

      expect(await provider.retryLocationPublishing(), isFalse);
    });

    test('a stream fix arriving later clears the failure', () async {
      location
        ..hangs = false
        ..nextPosition = null; // initial seed unavailable
      final provider = buildProvider();
      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));
      await provider.retryLocationPublishing();
      expect(provider.locationFailure, isNotNull);

      positionController.add(position());
      await Future<void>.delayed(Duration.zero);

      expect(
        provider.locationFailure,
        isNull,
        reason: 'a late fix must resume publishing without a new journey',
      );
    });
  });

  group('stale asynchronous work cannot mutate the wrong journey', () {
    test(
      'a fix resolving after the journey stopped does not publish',
      () async {
        location.hangs = true;
        final provider = buildProvider();
        await provider
            .startCoordination(journeyId)
            .timeout(const Duration(seconds: 5));

        // Hold the fix open so the ordering under test is deterministic: the
        // journey ends first, and only then does GPS answer.
        final gate = Completer<Position?>();
        location
          ..hangs = false
          ..gate = gate;
        final retry = provider.retryLocationPublishing();
        await provider.stopCoordination();
        gate.complete(position());
        await retry;

        expect(provider.currentJourneyId, isNull);
        verifyNever(
          publishMyPosition(
            journeyId: journeyId,
            latitude: anyNamed('latitude'),
            longitude: anyNamed('longitude'),
            timestamp: anyNamed('timestamp'),
            accuracy: anyNamed('accuracy'),
            altitude: anyNamed('altitude'),
            heading: anyNamed('heading'),
            speed: anyNamed('speed'),
            batteryLevel: anyNamed('batteryLevel'),
            isMoving: anyNamed('isMoving'),
          ),
        );
      },
    );

    test('a position tick for a previous journey is ignored', () async {
      location
        ..hangs = false
        ..nextPosition = position();
      final provider = buildProvider();
      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));

      // Switch journeys; the old stream may still emit briefly.
      await provider
          .startCoordination(otherJourneyId)
          .timeout(const Duration(seconds: 5));
      clearInteractions(publishMyPosition);

      positionController.add(position(lat: 1, lng: 2));
      await Future<void>.delayed(Duration.zero);

      // Nothing may be published against the journey we already left.
      verifyNever(
        publishMyPosition(
          journeyId: journeyId,
          latitude: anyNamed('latitude'),
          longitude: anyNamed('longitude'),
          timestamp: anyNamed('timestamp'),
          accuracy: anyNamed('accuracy'),
          altitude: anyNamed('altitude'),
          heading: anyNamed('heading'),
          speed: anyNamed('speed'),
          batteryLevel: anyNamed('batteryLevel'),
          isMoving: anyNamed('isMoving'),
        ),
      );
    });

    test('stopCoordination clears the location failure', () async {
      location.hangs = true;
      final provider = buildProvider();
      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));
      expect(provider.locationFailure, isNotNull);

      await provider.stopCoordination();

      expect(provider.locationFailure, isNull);
    });
  });

  group('room membership does not wait on the permission dialog', () {
    test(
      'subscription completes while permission is still unresolved',
      () async {
        // The OS dialog is held open for the whole test: the user has not
        // answered yet. Room membership must not be hostage to that.
        final dialog = Completer<({bool granted, Failure? failure})>();
        permission.pending = dialog;
        location.hangs = true;
        final provider = buildProvider();

        final starting = provider.startCoordination(journeyId);
        // Let the synchronous subscription work run.
        await Future<void>.delayed(Duration.zero);

        expect(
          provider.isSubscribed,
          isTrue,
          reason: 'room joined before the permission dialog was answered',
        );
        verify(streamConvoyPositions(journeyId)).called(1);
        expect(dialog.isCompleted, isFalse);

        // Now the user answers.
        dialog.complete((granted: true, failure: null));
        await starting.timeout(const Duration(seconds: 5));
      },
    );

    test('permission denial keeps room membership intact', () async {
      permission.result = (
        granted: false,
        failure: ConvoyFailure.locationPermissionDenied,
      );
      final provider = buildProvider();

      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));

      expect(provider.isSubscribed, isTrue);
      expect(provider.currentJourneyId, journeyId);
      expect(provider.locationFailure, isNotNull);
      expect(
        provider.isPublishing,
        isFalse,
        reason: 'nothing may publish without a grant',
      );
    });

    test('permission grant starts publishing', () async {
      location
        ..hangs = false
        ..nextPosition = position();
      final provider = buildProvider();

      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));

      expect(provider.isPublishing, isTrue);
      expect(provider.locationFailure, isNull);
    });

    test('a grant arriving after a journey switch does not publish', () async {
      final dialog = Completer<({bool granted, Failure? failure})>();
      permission.pending = dialog;
      location
        ..hangs = false
        ..nextPosition = position();
      final provider = buildProvider();

      final starting = provider.startCoordination(journeyId);
      await Future<void>.delayed(Duration.zero);
      await provider.stopCoordination();

      dialog.complete((granted: true, failure: null));
      await starting.timeout(const Duration(seconds: 5));

      expect(provider.currentJourneyId, isNull);
      expect(provider.isPublishing, isFalse);
    });
  });

  group('a throwing permission gate cannot corrupt provider state', () {
    test('room membership and journey id survive the exception', () async {
      permission.error = StateError('permission channel exploded');
      final provider = buildProvider();

      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));

      // The invariant: subscribed implies we know which journey we are in.
      expect(provider.isSubscribed, isTrue);
      expect(
        provider.currentJourneyId,
        journeyId,
        reason:
            'subscribed to a room the provider no longer identifies is the '
            'exact corrupt state this guards against',
      );
      verify(streamConvoyPositions(journeyId)).called(1);
    });

    test(
      'the failure is reported as a location problem, not a convoy one',
      () async {
        permission.error = StateError('permission channel exploded');
        final provider = buildProvider();

        await provider
            .startCoordination(journeyId)
            .timeout(const Duration(seconds: 5));

        expect(provider.locationFailure, isNotNull);
        expect(
          provider.errorMessage,
          isNull,
          reason: 'the convoy itself is fine; only location acquisition failed',
        );
        expect(provider.isPublishing, isFalse);
      },
    );
  });

  group('connection attempt identity is owned by the provider', () {
    test('starts at zero and increments when a journey is joined', () async {
      final provider = buildProvider();
      expect(provider.connectionAttemptId, 0);

      await provider
          .startCoordination(journeyId)
          .timeout(const Duration(seconds: 5));

      expect(provider.connectionAttemptId, 1);
    });

    test(
      'an explicit reconnect is a new attempt for the same journey',
      () async {
        when(repository.ensureLiveConnection()).thenAnswer((_) async {});
        when(repository.joinJourneyRoom(any)).thenAnswer((_) async {});
        final provider = buildProvider();
        await provider
            .startCoordination(journeyId)
            .timeout(const Duration(seconds: 5));
        final afterStart = provider.connectionAttemptId;

        await provider.reconnect(journeyId).timeout(const Duration(seconds: 5));

        expect(
          provider.connectionAttemptId,
          greaterThan(afterStart),
          reason:
              'journey id is unchanged, so only the attempt id can express '
              'that this is a fresh connection window',
        );
      },
    );

    test('ids are monotonic across journeys and reconnects', () async {
      when(repository.ensureLiveConnection()).thenAnswer((_) async {});
      when(repository.joinJourneyRoom(any)).thenAnswer((_) async {});
      final provider = buildProvider();
      final seen = <int>[];

      await provider.startCoordination(journeyId);
      seen.add(provider.connectionAttemptId);
      await provider.reconnect(journeyId);
      seen.add(provider.connectionAttemptId);
      await provider.startCoordination(otherJourneyId);
      seen.add(provider.connectionAttemptId);

      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]));
      }
    });
  });

  group('concurrent coordination starts', () {
    test('two rapid starts for the same journey share one attempt', () async {
      location.hangs = true;
      final provider = buildProvider();

      // Home screen and map screen both start coordination for the same
      // journey within the same navigation transition.
      await Future.wait([
        provider.startCoordination(journeyId),
        provider.startCoordination(journeyId),
      ]).timeout(const Duration(seconds: 5));

      verify(streamConvoyPositions(journeyId)).called(1);
    });
  });

  group('terminal publish reconciliation', () {
    test('JOURNEY_NOT_ACTIVE stops and publishes one terminal event', () async {
      location
        ..hangs = false
        ..nextPosition = position();
      when(
        publishMyPosition(
          journeyId: anyNamed('journeyId'),
          latitude: anyNamed('latitude'),
          longitude: anyNamed('longitude'),
          timestamp: anyNamed('timestamp'),
          accuracy: anyNamed('accuracy'),
          altitude: anyNamed('altitude'),
          heading: anyNamed('heading'),
          speed: anyNamed('speed'),
          batteryLevel: anyNamed('batteryLevel'),
          isMoving: anyNamed('isMoving'),
        ),
      ).thenAnswer(
        (_) async => (success: false, failure: ConvoyFailure.journeyNotActive),
      );
      when(repository.stopCoordination()).thenAnswer((_) async {});
      final provider = buildProvider();

      await provider.startCoordination(journeyId);

      expect(provider.currentJourneyId, isNull);
      expect(provider.isPublishing, isFalse);
      expect(provider.lastJourneyEndedEvent?.journeyId, journeyId);
      expect(provider.lastJourneyEndedEvent?.reason, 'terminal-reconciliation');
      verify(repository.stopCoordination()).called(1);
    });
  });
}

/// Test double for [LocationService].
///
/// Mirrors the production contract: [getCurrentPosition] must always settle,
/// returning null when no fix is obtainable.
class _FakeLocationService implements LocationService {
  _FakeLocationService(this._stream);

  final Stream<Position> _stream;

  /// When true, the device cannot produce a fix at all.
  bool hangs = false;

  /// Position returned by the next [getCurrentPosition] call.
  Position? nextPosition;

  /// When set, the fix is withheld until the test completes this gate.
  Completer<Position?>? gate;

  @override
  Future<Position?> getCurrentPosition({Duration? timeout}) async {
    final pending = gate;
    if (pending != null) return pending.future;
    if (hangs) return null;
    return nextPosition;
  }

  @override
  Future<Position?> getLastKnownPosition() async => hangs ? null : nextPosition;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _stream;
}

/// Test double for [LocationPermissionGate].
///
/// [pending] lets a test hold the OS dialog open indefinitely, which is how the
/// room-join ordering is proven rather than assumed.
class _FakePermissionGate implements LocationPermissionGate {
  ({bool granted, Failure? failure}) result = (granted: true, failure: null);
  Completer<({bool granted, Failure? failure})>? pending;

  /// When set, [request] throws instead of returning — modelling a broken
  /// platform channel rather than a normal denial.
  Object? error;

  @override
  Future<({bool granted, Failure? failure})> request() {
    final thrown = error;
    if (thrown != null) return Future.error(thrown);
    final held = pending;
    if (held != null) return held.future;
    return Future.value(result);
  }
}
