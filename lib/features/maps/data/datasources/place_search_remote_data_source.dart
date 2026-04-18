import 'package:dio/dio.dart';
import '../models/place_search_response_model.dart';

abstract class PlaceSearchRemoteDataSource {
  Future<PlaceSearchResponseModel> searchPlaces(String query);
}

class PlaceSearchRemoteDataSourceImpl implements PlaceSearchRemoteDataSource {
  final Dio dio;

  PlaceSearchRemoteDataSourceImpl({required this.dio});

  @override
  Future<PlaceSearchResponseModel> searchPlaces(String query) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/maps/search',
        queryParameters: {'query': query},
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
        message: 'Network error while searching places: ${e.message}',
        error: e.error,
      );
    } catch (e) {
      throw Exception('Unexpected error while searching places: $e');
    }
  }
}