import 'package:dio/dio.dart';
import '../models/place_search_response_model.dart';

abstract class PlaceSearchRemoteDataSource {
  Future<PlaceSearchResponseModel> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    String? regionCode,
  });
}

class PlaceSearchRemoteDataSourceImpl implements PlaceSearchRemoteDataSource {
  final Dio dio;

  PlaceSearchRemoteDataSourceImpl({required this.dio});

  @override
  Future<PlaceSearchResponseModel> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    String? regionCode,
  }) async {
    try {
      final queryParams = <String, dynamic>{'query': query};
      if (lat != null) queryParams['lat'] = lat;
      if (lng != null) queryParams['lng'] = lng;
      if (regionCode != null) queryParams['regionCode'] = regionCode;

      final response = await dio.get<Map<String, dynamic>>(
        '/maps/search',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        return PlaceSearchResponseModel.fromJson(response.data!);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Failed to search places: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      throw DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        // Preserve the original type (connectionError / badResponse / cancel /
        // timeout) — defaulting to `unknown` is what made the repository
        // mislabel server/parse/cancel errors as "no internet".
        type: e.type,
        message: 'Network error while searching places: ${e.message}',
        error: e.error,
      );
    } catch (e) {
      throw Exception('Unexpected error while searching places: $e');
    }
  }
}