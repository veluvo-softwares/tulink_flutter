import 'package:dio/dio.dart';
import '../../../../core/config/app_config.dart';

class MapboxSearchResult {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  MapboxSearchResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

class MapboxSearchDataSource {
  final Dio dio;

  MapboxSearchDataSource({required this.dio});

  Future<List<MapboxSearchResult>> search(String query) async {
    if (query.isEmpty) return [];

    final accessToken = AppConfig.mapboxAccessToken;
    final url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json';

    try {
      final response = await dio.get<Map<String, dynamic>>(
        url,
        queryParameters: {
          'access_token': accessToken,
          'limit': 5,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final features = response.data!['features'] as List<dynamic>?;
        if (features != null) {
          return features.map((feature) {
            final featureMap = feature as Map<String, dynamic>;
            final center = featureMap['center'] as List<dynamic>;
            return MapboxSearchResult(
              name: featureMap['text']?.toString() ?? '',
              address: featureMap['place_name']?.toString() ?? '',
              latitude: (center[1] as num).toDouble(),
              longitude: (center[0] as num).toDouble(),
            );
          }).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
