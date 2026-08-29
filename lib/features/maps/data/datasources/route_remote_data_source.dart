import 'dart:math';

import 'package:dio/dio.dart';
import '../models/route_result_model.dart';

abstract class RouteRemoteDataSource {
  Future<RouteResultModel?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  });

  Future<RouteResultModel?> getCanonicalRoute(String journeyId);

  Future<RouteResultModel?> replaceCanonicalRoute({
    required String journeyId,
    required double originLat,
    required double originLng,
    required int baseVersion,
    required String reason,
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

      print(
        '✅ Route fetched: '
        '${route.coordinates.length} coordinates, '
        '${route.steps.length} steps, '
        '${route.distanceMetres.toStringAsFixed(0)}m',
      );

      return route;
    } catch (e) {
      print('⚠️ Route fetch failed: $e');
      return null;
    }
  }

  @override
  Future<RouteResultModel?> getCanonicalRoute(String journeyId) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/journeys/$journeyId/route',
      );
      if (response.statusCode != 200 || response.data == null) return null;
      final data = response.data!['data'];
      if (data == null) return null;
      if (data is! Map) return null;
      final route = RouteResultModel.fromJson(data.cast<String, dynamic>());
      return route.coordinates.isEmpty ? null : route;
    } catch (error) {
      print('⚠️ Canonical route fetch failed: $error');
      return null;
    }
  }

  @override
  Future<RouteResultModel?> replaceCanonicalRoute({
    required String journeyId,
    required double originLat,
    required double originLng,
    required int baseVersion,
    required String reason,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/journeys/$journeyId/route',
        data: {
          'originLat': originLat,
          'originLng': originLng,
          'baseVersion': baseVersion,
          'reason': reason,
          'requestId': _uuidV4(),
        },
      );
      final data = response.data?['data'];
      if (response.statusCode != 200 || data is! Map) return null;
      final route = RouteResultModel.fromJson(data.cast<String, dynamic>());
      return route.coordinates.isEmpty ? null : route;
    } on DioException catch (error) {
      // Another leader request won the compare-and-swap. Reading the committed
      // winner converges this client without calculating a competing route.
      if (error.response?.statusCode == 409) {
        return getCanonicalRoute(journeyId);
      }
      print('⚠️ Canonical route update failed: $error');
      return null;
    }
  }

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
