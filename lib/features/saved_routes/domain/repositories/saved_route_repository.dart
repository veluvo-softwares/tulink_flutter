import '../../../../core/common/result.dart';
import '../entities/saved_route.dart';

abstract class SavedRouteRepository {
  Future<Result<List<SavedRoute>>> list();

  Future<Result<SavedRoute>> create({
    required String name,
    String? description,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  });

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
  });

  Future<BoolResult> archive(String id);
}
