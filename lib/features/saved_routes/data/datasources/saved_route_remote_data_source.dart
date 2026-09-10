import 'package:dio/dio.dart';

import '../../domain/entities/saved_route.dart';
import '../models/saved_route_model.dart';

class SavedRouteRemoteDataSource {
  const SavedRouteRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<SavedRouteModel>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/saved-routes');
    final data = response.data?['data'];
    if (data is! List) throw const FormatException('Invalid saved routes');
    return data
        .whereType<Map<Object?, Object?>>()
        .map((route) => SavedRouteModel.fromJson(route.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<SavedRouteModel> create({
    required String name,
    String? description,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/saved-routes',
      data: _writePayload(
        name: name,
        description: description,
        source: source,
        waypoints: waypoints,
        geometry: geometry,
        routeIndex: routeIndex,
        recordedDurationSeconds: recordedDurationSeconds,
      ),
    );
    return _routeFromResponse(response);
  }

  Future<SavedRouteModel> update({
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
    final response = await _dio.put<Map<String, dynamic>>(
      '/saved-routes/$id',
      data: _writePayload(
        name: name,
        description: description,
        source: source,
        waypoints: waypoints,
        geometry: geometry,
        routeIndex: routeIndex,
        recordedDurationSeconds: recordedDurationSeconds,
        expectedVersion: expectedVersion,
      ),
    );
    return _routeFromResponse(response);
  }

  SavedRouteModel _routeFromResponse(Response<Map<String, dynamic>> response) {
    final data = response.data?['data'];
    if (data is! Map) throw const FormatException('Invalid saved route');
    return SavedRouteModel.fromJson(data.cast<String, dynamic>());
  }

  Map<String, dynamic> _writePayload({
    required String name,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    String? description,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
    int? expectedVersion,
  }) => {
    'name': name,
    if (description != null && description.trim().isNotEmpty)
      'description': description.trim(),
    'source': source.name.toUpperCase(),
    'waypoints': waypoints
        .map(
          (point) => {
            'latitude': point.latitude,
            'longitude': point.longitude,
            if (point.name != null) 'name': point.name,
          },
        )
        .toList(growable: false),
    if (geometry != null)
      'geometry': geometry
          .map((point) => {'longitude': point[0], 'latitude': point[1]})
          .toList(growable: false),
    'routeIndex': routeIndex,
    if (recordedDurationSeconds != null)
      'recordedDurationSeconds': recordedDurationSeconds,
    if (expectedVersion != null) 'expectedVersion': expectedVersion,
  };

  Future<void> archive(String id) async {
    final response = await _dio.delete<void>('/saved-routes/$id');
    if (response.statusCode != 204) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Could not archive saved route',
      );
    }
  }
}
