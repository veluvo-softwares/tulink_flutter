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

      if (response.statusCode == 200 && response.data != null) {
        return RouteResultModel.fromJson(response.data!);
      }
      return null;
    } catch (e) {
      print('⚠️ Route fetch failed: $e');
      return null;
    }
  }
}
