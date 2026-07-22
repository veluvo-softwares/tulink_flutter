import '../../../../core/services/offline_storage_service.dart';
import '../models/race_route_model.dart';
import '../models/route_result_model.dart';

abstract class MapLocalDataSource {
  Future<RaceRouteModel?> loadMarathonRoute();
  Future<RouteResultModel?> loadRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  });
  Future<void> saveRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required RouteResultModel route,
  });
}

class MapLocalDataSourceImpl implements MapLocalDataSource {
  MapLocalDataSourceImpl(this._storage);

  final OfflineStorageService _storage;

  @override
  Future<RaceRouteModel?> loadMarathonRoute() async {
    return null;
  }

  @override
  Future<RouteResultModel?> loadRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final value = OfflineStorageService.readMap(
      _storage.routes.get(_storage.routeKey(userId, journeyId)),
    );
    if (value == null || value['schemaVersion'] != 1) return null;
    if (value['userId'] != userId || value['journeyId'] != journeyId) {
      return null;
    }
    final storedLat = (value['destinationLat'] as num?)?.toDouble();
    final storedLng = (value['destinationLng'] as num?)?.toDouble();
    if (storedLat == null || storedLng == null) return null;
    if ((storedLat - destinationLat).abs() >= 0.001 ||
        (storedLng - destinationLng).abs() >= 0.001) {
      return null;
    }
    final routeJson = OfflineStorageService.readMap(value['route']);
    if (routeJson == null) return null;
    try {
      final route = RouteResultModel.fromJson(routeJson);
      return route.coordinates.length >= 2 ? route : null;
    } catch (error) {
      print('⚠️ Discarding corrupt offline route: $error');
      return null;
    }
  }

  @override
  Future<void> saveRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required RouteResultModel route,
  }) async {
    final savedAt = DateTime.now().toUtc().toIso8601String();
    await _storage.routes.put(_storage.routeKey(userId, journeyId), {
      'schemaVersion': 1,
      'userId': userId,
      'journeyId': journeyId,
      'originLat': originLat,
      'originLng': originLng,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'savedAt': savedAt,
      'route': route.toJson(),
    });
    await _storage.mergeSession(userId, journeyId, {
      'route': route.toJson(),
      'routeOrigin': {'latitude': originLat, 'longitude': originLng},
      'routeDestination': {
        'latitude': destinationLat,
        'longitude': destinationLng,
      },
      'routeRevision': savedAt,
      'mapStyleUri': 'mapbox://styles/mapbox/dark-v11',
    });
  }
}
