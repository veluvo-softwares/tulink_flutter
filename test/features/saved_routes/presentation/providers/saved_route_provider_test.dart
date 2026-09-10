import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/saved_routes/domain/entities/saved_route.dart';
import 'package:tulink_flutter/features/saved_routes/domain/repositories/saved_route_repository.dart';
import 'package:tulink_flutter/features/saved_routes/presentation/providers/saved_route_provider.dart';

void main() {
  final original = route(version: 1, name: 'Old route');
  final updated = route(version: 2, name: 'New route');

  test('updates a route in place after an optimistic save', () async {
    final repository = _FakeSavedRouteRepository(routes: [original]);
    final provider = SavedRouteProvider(repository);
    await provider.load();
    repository.updated = updated;

    final result = await provider.update(
      existing: original,
      name: updated.name,
      source: updated.source,
      waypoints: updated.waypoints,
      geometry: updated.geometry,
    );

    expect(result, updated);
    expect(provider.routes, [updated]);
    expect(repository.lastExpectedVersion, 1);
  });

  test('removes an archived route from the library', () async {
    final repository = _FakeSavedRouteRepository(routes: [original]);
    final provider = SavedRouteProvider(repository);
    await provider.load();

    expect(await provider.archive(original.id), isTrue);
    expect(provider.routes, isEmpty);
  });
}

SavedRoute route({required int version, required String name}) => SavedRoute(
  id: 'route-1',
  organizationId: 'org-1',
  name: name,
  source: SavedRouteSource.recorded,
  geometry: const [
    [36.8, -1.2],
    [36.9, -1.3],
  ],
  waypoints: const [
    SavedRouteWaypoint(latitude: -1.2, longitude: 36.8),
    SavedRouteWaypoint(latitude: -1.3, longitude: 36.9),
  ],
  distanceMetres: 15000,
  durationSeconds: 1200,
  steps: const [],
  version: version,
  canEdit: true,
  editorUserIds: const [],
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 9),
);

class _FakeSavedRouteRepository implements SavedRouteRepository {
  _FakeSavedRouteRepository({required this.routes});

  final List<SavedRoute> routes;
  SavedRoute? updated;
  int? lastExpectedVersion;

  @override
  Future<Result<List<SavedRoute>>> list() async => ResultHelper.success(routes);

  @override
  Future<Result<SavedRoute>> create({
    required String name,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    String? description,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  }) async => ResultHelper.success(route(version: 1, name: name));

  @override
  Future<Result<SavedRoute>> update({
    required String id,
    required int expectedVersion,
    required String name,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    String? description,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  }) async {
    lastExpectedVersion = expectedVersion;
    return ResultHelper.success(updated!);
  }

  @override
  Future<BoolResult> archive(String id) async => ResultHelper.successBool();
}
