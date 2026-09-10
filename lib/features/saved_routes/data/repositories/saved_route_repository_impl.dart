import '../../../../core/common/result.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/saved_route.dart';
import '../../domain/repositories/saved_route_repository.dart';
import '../datasources/saved_route_remote_data_source.dart';

class SavedRouteRepositoryImpl implements SavedRouteRepository {
  const SavedRouteRepositoryImpl(this._remote);

  final SavedRouteRemoteDataSource _remote;

  @override
  Future<Result<List<SavedRoute>>> list() async {
    try {
      return ResultHelper.success(await _remote.list());
    } catch (_) {
      return ResultHelper.failure(
        ServerFailure(message: 'Could not load saved routes'),
      );
    }
  }

  @override
  Future<Result<SavedRoute>> create({
    required String name,
    String? description,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  }) async {
    try {
      return ResultHelper.success(
        await _remote.create(
          name: name,
          description: description,
          source: source,
          waypoints: waypoints,
          geometry: geometry,
          routeIndex: routeIndex,
          recordedDurationSeconds: recordedDurationSeconds,
        ),
      );
    } catch (_) {
      return ResultHelper.failure(
        ServerFailure(message: 'Could not save this route'),
      );
    }
  }

  @override
  Future<BoolResult> archive(String id) async {
    try {
      await _remote.archive(id);
      return ResultHelper.successBool();
    } catch (_) {
      return ResultHelper.failureBool(
        ServerFailure(message: 'Could not remove this route'),
      );
    }
  }

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
    try {
      return ResultHelper.success(
        await _remote.update(
          id: id,
          expectedVersion: expectedVersion,
          name: name,
          description: description,
          source: source,
          waypoints: waypoints,
          geometry: geometry,
          routeIndex: routeIndex,
          recordedDurationSeconds: recordedDurationSeconds,
        ),
      );
    } catch (_) {
      return ResultHelper.failure(
        ServerFailure(message: 'Could not update this route'),
      );
    }
  }
}
