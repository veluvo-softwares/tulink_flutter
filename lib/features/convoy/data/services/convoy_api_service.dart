import 'package:dio/dio.dart';

import '../models/location_update_dto.dart';

/// API service for convoy coordination REST endpoints
/// Handles location publishing and snapshot fetching via HTTP
class ConvoyApiService {
  ConvoyApiService(this._dio);

  final Dio _dio;

  /// Publish location update to the convoy
  /// POST /locations
  /// Rate limited to 60 updates/minute per user per journey
  Future<Map<String, dynamic>> publishLocation(
    LocationUpdateDto locationUpdate,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/locations',
        data: locationUpdate.toJson(),
      );

      if (response.data == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'Empty response from server',
        );
      }

      return response.data!;
    } on DioException catch (e) {
      // Handle rate limiting specifically
      if (e.response?.statusCode == 429) {
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: DioExceptionType.badResponse,
          error: 'Location update rate limit exceeded. Please slow down.',
        );
      }

      // Re-throw other Dio exceptions as-is
      rethrow;
    } catch (e) {
      // Wrap other exceptions in DioException for consistent error handling
      throw DioException(
        requestOptions: RequestOptions(path: '/locations'),
        type: DioExceptionType.unknown,
        error: 'Unexpected error publishing location: $e',
      );
    }
  }

  Future<Map<String, dynamic>> backfillLocations({
    required String journeyId,
    required String batchId,
    required List<Map<String, dynamic>> points,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/locations/backfill',
      data: {'journeyId': journeyId, 'batchId': batchId, 'points': points},
    );
    final body = response.data;
    if (body == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty backfill response',
      );
    }
    final data = body['data'];
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : body;
  }

  /// Fetch latest convoy snapshot for cold start
  /// GET /locations/journeys/{journeyId}/latest
  Future<Map<String, dynamic>> fetchLatestPositions(String journeyId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/locations/journeys/$journeyId/latest',
      );

      if (response.data == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'Empty response from server',
        );
      }

      final body = response.data!;
      final data = body['data'];
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
      return body;
    } on DioException catch (e) {
      // Handle journey not found specifically
      if (e.response?.statusCode == 404) {
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: DioExceptionType.badResponse,
          error: 'Journey not found or no members have shared positions yet.',
        );
      }

      // Re-throw other Dio exceptions as-is
      rethrow;
    } catch (e) {
      // Wrap other exceptions in DioException for consistent error handling
      throw DioException(
        requestOptions: RequestOptions(
          path: '/locations/journeys/$journeyId/latest',
        ),
        type: DioExceptionType.unknown,
        error: 'Unexpected error fetching convoy positions: $e',
      );
    }
  }

  /// Fetch the authoritative state used to recover a live journey after a
  /// cold start, reconnect, or foreground resume.
  /// GET /journeys/{journeyId}/live
  Future<Map<String, dynamic>> fetchLiveJourneySnapshot(
    String journeyId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/journeys/$journeyId/live',
    );
    final body = response.data;
    if (body == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty live journey response from server',
      );
    }

    final data = body['data'];
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return body;
  }
}
