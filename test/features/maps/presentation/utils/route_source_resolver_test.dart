import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tulink_flutter/core/services/location_service.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';
import 'package:tulink_flutter/features/maps/presentation/utils/route_source_resolver.dart';

/// Regression suite for route-source ordering.
///
/// The defect: the live screen acquired a GPS position *before* checking
/// whether a matching preview route was already cached, and bailed out early
/// when no fix was available. A device without a fix therefore discarded a
/// perfectly good route it already had, leaving the live map with no polyline.
void main() {
  // Karen Shopping Centre, the destination from the original failure.
  const destLat = -1.3234931;
  const destLng = 36.7083102;

  RouteResultModel routeEndingAt(double lng, double lat) => RouteResultModel(
    coordinates: [
      [36.8219, -1.2921],
      [lng, lat],
    ],
    distanceMetres: 15355,
    durationSeconds: 1500,
    steps: const [],
  );

  late _FakeLocationService location;

  setUp(() => location = _FakeLocationService());

  group('cached route is preferred and needs no location', () {
    test('a matching cached route is used when the fix is null', () async {
      location.position = null; // device cannot produce a fix

      final source = await resolveRouteSource(
        cachedRoute: routeEndingAt(destLng, destLat),
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      expect(source, isA<CachedRouteSource>());
      expect(
        (source as CachedRouteSource).route.distanceMetres,
        15355,
        reason: 'the cached geometry must be handed back intact',
      );
    });

    test('the cached check happens BEFORE location is acquired', () async {
      location.position = null;

      await resolveRouteSource(
        cachedRoute: routeEndingAt(destLng, destLat),
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      expect(
        location.getCurrentPositionCalls,
        0,
        reason: 'a usable cached route must not trigger any GPS work',
      );
    });

    test(
      'a known origin is also ignored when a cached route matches',
      () async {
        final source = await resolveRouteSource(
          cachedRoute: routeEndingAt(destLng, destLat),
          destinationLat: destLat,
          destinationLng: destLng,
          locationService: location,
          knownLat: -1.2921,
          knownLng: 36.8219,
        );

        expect(source, isA<CachedRouteSource>());
        expect(location.getCurrentPositionCalls, 0);
      },
    );

    test('tolerates a route snapped slightly off the destination', () async {
      // Route providers snap the final point to the road network.
      final source = await resolveRouteSource(
        cachedRoute: routeEndingAt(destLng + 0.0005, destLat - 0.0005),
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      expect(source, isA<CachedRouteSource>());
    });
  });

  group('a stale or absent cached route falls through to a fetch', () {
    test('a route for a different destination is not reused', () async {
      location.position = _position(-1.2921, 36.8219);

      final source = await resolveRouteSource(
        cachedRoute: routeEndingAt(36.8219, -1.2921), // Nairobi CBD, not Karen
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      expect(source, isA<FetchRouteSource>());
      expect(location.getCurrentPositionCalls, 1);
    });

    test('a null cached route acquires an origin', () async {
      location.position = _position(-1.2921, 36.8219);

      final source = await resolveRouteSource(
        cachedRoute: null,
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      expect(source, isA<FetchRouteSource>());
      final fetch = source as FetchRouteSource;
      expect(fetch.originLat, -1.2921);
      expect(fetch.originLng, 36.8219);
    });

    test('an empty cached route is not treated as a match', () async {
      location.position = _position(-1.2921, 36.8219);

      final source = await resolveRouteSource(
        cachedRoute: RouteResultModel(
          coordinates: const [],
          distanceMetres: 0,
          durationSeconds: 0,
          steps: const [],
        ),
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      expect(source, isA<FetchRouteSource>());
    });

    test('a supplied origin avoids re-acquiring a position', () async {
      final source = await resolveRouteSource(
        cachedRoute: null,
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
        knownLat: 1.5,
        knownLng: 2.5,
      );

      expect(source, isA<FetchRouteSource>());
      expect((source as FetchRouteSource).originLat, 1.5);
      expect(location.getCurrentPositionCalls, 0);
    });
  });

  group('no cached route and no origin is recoverable', () {
    test('yields AwaitingLocation rather than silently giving up', () async {
      location.position = null;

      final source = await resolveRouteSource(
        cachedRoute: null,
        destinationLat: destLat,
        destinationLng: destLng,
        locationService: location,
      );

      // The caller keeps the destination marker, centres on it, and retries
      // when a fix arrives — rather than leaving a blank regional map.
      expect(source, isA<AwaitingLocationRouteSource>());
      expect(location.getCurrentPositionCalls, 1);
    });
  });

  group('routeEndsAtDestination', () {
    test('rejects a malformed coordinate', () {
      expect(routeEndsAtDestination(const [36.7], destLng, destLat), isFalse);
      expect(routeEndsAtDestination(const [], destLng, destLat), isFalse);
    });

    test('rejects a point beyond the tolerance', () {
      expect(
        routeEndsAtDestination(const [36.75, -1.32], destLng, destLat),
        isFalse,
      );
    });
  });
}

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.utc(2026, 8, 15),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _FakeLocationService implements LocationService {
  Position? position;
  int getCurrentPositionCalls = 0;

  @override
  Future<Position?> getCurrentPosition({Duration? timeout}) async {
    getCurrentPositionCalls++;
    return position;
  }

  @override
  Future<Position?> getLastKnownPosition() async => position;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream<Position>.empty();
}
