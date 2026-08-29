import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';
import 'package:tulink_flutter/features/maps/domain/entities/place_search_result.dart';
import 'package:tulink_flutter/features/maps/domain/entities/race_route.dart';
import 'package:tulink_flutter/features/maps/domain/repositories/map_repository.dart';
import 'package:tulink_flutter/features/maps/domain/usecases/search_places_usecase.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/map_provider.dart';

/// Route state may only be mutated by the request that is still current under
/// its **full** identity: user/session, journey, destination, request
/// generation, and the map surface generation.
///
/// The network path was already guarded. The cache path was not: `fetchRoute`
/// created a token and then awaited `_drawCachedRoute`, which wrote
/// `_currentRoute` and notified unconditionally — so a slow cache lookup for
/// journey A overwrote journey B's freshly fetched route.
void main() {
  late _FakeMapRepository repository;
  late MapProvider provider;

  /// A route whose identity is carried in a synthetic step, so two otherwise
  /// identical routes can be told apart.
  RouteResultModel tagged(String tag, {int? version}) => RouteResultModel(
    coordinates: [
      [36.0, -1.0],
      [36.1, -1.1],
    ],
    distanceMetres: 1000,
    durationSeconds: 600,
    steps: [
      RouteStepModel(instruction: tag, distanceMetres: 1, maneuver: 'depart'),
    ],
    canonicalVersion: version,
    canonicalReason: version == null ? null : 'INITIAL',
  );

  String? tagOf(RouteResultModel? r) =>
      r?.steps.isEmpty ?? true ? null : r!.steps.first.instruction;

  setUp(() {
    repository = _FakeMapRepository();
    provider = MapProvider(
      repository,
      SearchPlacesUseCase(repository: repository),
    );
  });

  Future<RouteResultModel?> fetch({
    String userId = 'u1',
    String journeyId = 'A',
    double destLat = -1.0,
    double destLng = 36.0,
    int? surfaceGeneration,
  }) => provider.fetchRoute(
    userId: userId,
    journeyId: journeyId,
    originLat: 0,
    originLng: 0,
    destLat: destLat,
    destLng: destLng,
    surfaceGeneration: surfaceGeneration,
  );

  test('a slow cached route for A cannot overwrite a fast fetched B', () async {
    // The exact shipped race. A's cache read is slow; B fetches and installs
    // first; A's cache then lands.
    final cacheGateA = Completer<RouteResultModel?>();
    repository.cachedFor['A'] = cacheGateA.future;
    repository.cachedFor['B'] = Future.value(null);
    final networkGateA = Completer<RouteResultModel?>();
    repository.routeFor['A'] = networkGateA.future;
    repository.routeFor['B'] = Future.value(tagged('B-network'));

    final a = fetch(journeyId: 'A');
    final b = fetch(journeyId: 'B', destLat: -2, destLng: 37);
    await b;

    expect(tagOf(provider.currentRoute), 'B-network');

    // A's cache finally answers.
    cacheGateA.complete(tagged('A-cache'));
    await Future<void>.delayed(Duration.zero);

    expect(
      tagOf(provider.currentRoute),
      'B-network',
      reason: "a superseded cache read must not overwrite B's route",
    );

    // A's network answer arrives last, and is also rejected.
    networkGateA.complete(tagged('A-network'));
    expect(await a, isNull);
    expect(tagOf(provider.currentRoute), 'B-network');
  });

  test('a fast cached B is not undone by a slow cached A', () async {
    final cacheGateA = Completer<RouteResultModel?>();
    repository.cachedFor['A'] = cacheGateA.future;
    repository.cachedFor['B'] = Future.value(tagged('B-cache'));
    repository.routeFor['A'] = Completer<RouteResultModel?>().future;
    repository.routeFor['B'] = Completer<RouteResultModel?>().future;

    unawaited(fetch(journeyId: 'A'));
    unawaited(fetch(journeyId: 'B', destLat: -2, destLng: 37));
    await Future<void>.delayed(Duration.zero);
    expect(tagOf(provider.currentRoute), 'B-cache');

    cacheGateA.complete(tagged('A-cache'));
    await Future<void>.delayed(Duration.zero);
    expect(tagOf(provider.currentRoute), 'B-cache');
  });

  test(
    'clearing the draft invalidates a cache read already in flight',
    () async {
      final cacheGate = Completer<RouteResultModel?>();
      repository.cachedFor['A'] = cacheGate.future;
      repository.routeFor['A'] = Completer<RouteResultModel?>().future;

      unawaited(fetch(journeyId: 'A'));
      await Future<void>.delayed(Duration.zero);

      // What Home does on draft clear.
      provider.invalidateRouteRequests();

      cacheGate.complete(tagged('A-cache'));
      await Future<void>.delayed(Duration.zero);

      expect(
        provider.currentRoute,
        isNull,
        reason:
            'a cleared draft must not have its route painted a moment later',
      );
      expect(provider.isFetchingRoute, isFalse);
    },
  );

  test(
    'a surface rebuild invalidates work captured against the old one',
    () async {
      final cacheGate = Completer<RouteResultModel?>();
      repository.cachedFor['A'] = cacheGate.future;
      repository.routeFor['A'] = Future.value(tagged('A-network'));

      final pending = fetch(journeyId: 'A', surfaceGeneration: 0);
      await Future<void>.delayed(Duration.zero);

      // Resume rebuilt the native surface.
      provider.onSurfaceGenerationChanged(1);

      cacheGate.complete(tagged('A-cache'));
      expect(await pending, isNull);
      expect(
        provider.currentRoute,
        isNull,
        reason: 'nothing resolved against the old surface may become current',
      );
    },
  );

  test('a route is never handed to a different user session', () async {
    repository.cachedFor['A'] = Future.value(null);
    repository.routeFor['A'] = Future.value(tagged('u1-route'));

    await fetch(userId: 'u1', journeyId: 'A');
    expect(
      tagOf(
        provider.routeFor(
          userId: 'u1',
          journeyId: 'A',
          destLat: -1.0,
          destLng: 36.0,
        ),
      ),
      'u1-route',
    );

    expect(
      provider.routeFor(
        userId: 'u2',
        journeyId: 'A',
        destLat: -1.0,
        destLng: 36.0,
      ),
      isNull,
      reason: "another session must never read this session's route",
    );
    expect(
      provider.routeFor(
        userId: 'u1',
        journeyId: 'B',
        destLat: -1.0,
        destLng: 36.0,
      ),
      isNull,
      reason: "another journey must never read this journey's route",
    );
    expect(
      provider.routeFor(
        userId: 'u1',
        journeyId: 'A',
        destLat: -9.0,
        destLng: 36.0,
      ),
      isNull,
      reason: 'a different destination is a different route',
    );

    // Account switch drops it entirely.
    provider.onUserChanged('u2');
    expect(provider.currentRoute, isNull);
  });

  test('a superseded request never clears the newer loading flag', () async {
    repository.cachedFor['A'] = Future.value(null);
    repository.cachedFor['B'] = Future.value(null);
    final gateA = Completer<RouteResultModel?>();
    repository.routeFor['A'] = gateA.future;
    repository.routeFor['B'] = Completer<RouteResultModel?>().future;

    unawaited(fetch(journeyId: 'A'));
    unawaited(fetch(journeyId: 'B', destLat: -2, destLng: 37));
    await Future<void>.delayed(Duration.zero);

    gateA.complete(tagged('A-network'));
    await Future<void>.delayed(Duration.zero);

    expect(
      provider.isFetchingRoute,
      isTrue,
      reason: "A finishing must not report B's fetch as done",
    );
  });

  test('clearRoute abandons the request that would undo it', () async {
    repository.cachedFor['A'] = Future.value(null);
    final gate = Completer<RouteResultModel?>();
    repository.routeFor['A'] = gate.future;

    unawaited(fetch(journeyId: 'A'));
    await Future<void>.delayed(Duration.zero);
    provider.clearRoute();

    gate.complete(tagged('A-network'));
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentRoute, isNull);
  });

  test('canonical route version is installed for the exact journey', () async {
    repository.canonicalFor['A'] = Future.value(
      tagged('canonical', version: 3),
    );

    final route = await provider.fetchCanonicalRoute(
      userId: 'u1',
      journeyId: 'A',
      destLat: -1,
      destLng: 36,
    );

    expect(route?.canonicalVersion, 3);
    expect(
      provider.canonicalVersionFor(
        userId: 'u1',
        journeyId: 'A',
        destLat: -1,
        destLng: 36,
      ),
      3,
    );
  });

  test('a stale canonical response cannot overwrite a newer journey', () async {
    final a = Completer<RouteResultModel?>();
    repository.canonicalFor['A'] = a.future;
    repository.canonicalFor['B'] = Future.value(tagged('B', version: 2));

    final first = provider.fetchCanonicalRoute(
      userId: 'u1',
      journeyId: 'A',
      destLat: -1,
      destLng: 36,
    );
    await provider.fetchCanonicalRoute(
      userId: 'u1',
      journeyId: 'B',
      destLat: -2,
      destLng: 37,
    );
    a.complete(tagged('A', version: 1));

    expect(await first, isNull);
    expect(tagOf(provider.currentRoute), 'B');
  });

  test('leader replacement forwards compare-and-swap metadata', () async {
    repository.replacementFor['A'] = Future.value(
      tagged('reroute', version: 4),
    );

    await provider.replaceCanonicalRoute(
      userId: 'u1',
      journeyId: 'A',
      originLat: -1.2,
      originLng: 36.8,
      destLat: -1,
      destLng: 36,
      baseVersion: 3,
      reason: 'LEADER_REROUTE',
    );

    expect(repository.lastBaseVersion, 3);
    expect(repository.lastReason, 'LEADER_REROUTE');
    expect(provider.currentRoute?.canonicalVersion, 4);
  });
}

class _FakeMapRepository implements MapRepository {
  final Map<String, Future<RouteResultModel?>> routeFor = {};
  final Map<String, Future<RouteResultModel?>> cachedFor = {};
  final Map<String, Future<RouteResultModel?>> canonicalFor = {};
  final Map<String, Future<RouteResultModel?>> replacementFor = {};
  int? lastBaseVersion;
  String? lastReason;

  @override
  Future<RouteResultModel?> getRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) => routeFor[journeyId] ?? Future.value(null);

  @override
  Future<RouteResultModel?> getCachedRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  }) => cachedFor[journeyId] ?? Future.value(null);

  @override
  Future<RouteResultModel?> getCanonicalRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  }) => canonicalFor[journeyId] ?? Future.value(null);

  @override
  Future<RouteResultModel?> replaceCanonicalRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required int baseVersion,
    required String reason,
  }) {
    lastBaseVersion = baseVersion;
    lastReason = reason;
    return replacementFor[journeyId] ?? Future.value(null);
  }

  @override
  Future<RaceRoute?> getMarathonRoute() async => null;

  @override
  Future<Result<List<PlaceSearchResult>>> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    String? regionCode,
  }) async => (data: <PlaceSearchResult>[], failure: null);
}
