import 'package:dio/dio.dart';
import '../models/route_result_model.dart';

abstract class RouteRemoteDataSource {
  Future<RouteResultModel?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  });
}

class RouteRemoteDataSourceImpl implements RouteRemoteDataSource {
  final Dio dio;
  RouteRemoteDataSourceImpl({required this.dio});

  @override
  Future<RouteResultModel?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/maps/route',
        data: {
          'originLat': originLat,
          'originLng': originLng,
          'destLat': destLat,
          'destLng': destLng,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        print('⚠️ Route fetch returned non-200 or empty body');
        return null;
      }

      // API envelope: { success, statusCode, message, data: { ... } }
      final body = response.data!;
      final dataField = body['data'];
      if (dataField is! Map<String, dynamic>) {
        print('⚠️ Route response missing or malformed "data" field');
        return null;
      }

      final route = RouteResultModel.fromJson(dataField);

      if (route.coordinates.isEmpty) {
        print('⚠️ Route response parsed but contains no coordinates');
        return null;
      }

      print('✅ Route fetched: '
          '${route.coordinates.length} coordinates, '
          '${route.steps.length} steps, '
          '${route.distanceMetres.toStringAsFixed(0)}m');

      return route;
    } catch (e) {
      print('⚠️ Route fetch failed: $e');
      return null;
    }
  }
}
