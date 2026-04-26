import 'package:dio/dio.dart';

import 'package:tulink_flutter/core/network/api_handler.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';

/// Analytics API service following Retrofit pattern
/// Contains clean method signatures that delegate to ApiHandler
/// All route definitions are centralized in ApiRoutes
/// Zero hardcoded strings in this class
class AnalyticsApiService {
  /// Constructor that takes a Dio instance
  AnalyticsApiService(this._dio);

  final Dio _dio;

  /// Get user analytics data with optional limit (recent journeys)
  /// Returns standardized response with user journey data
  // Future<Map<String, dynamic>> getUserAnalytics({int? limit}) {
  //   final queryParams = <String, dynamic>{};
  //   if (limit != null) {
  //     queryParams['limit'] = limit;
  //   }

  //   return ApiHandler.performApiCall<Map<String, dynamic>>(
  //     () => _dio.get<Map<String, dynamic>>(
  //       ApiRoutes.userAnalytics,
  //       queryParameters: queryParams,
  //     ),
  //     (data) => data,
  //   );
  // }

  /// Get user journey history with pagination
  Future<Map<String, dynamic>> getUserJourneyHistory({
    int? limit,
  }) async {
    final queryParams = <String, dynamic>{};
    if (limit != null) {
      queryParams['limit'] = limit;
    }
    
    return ApiHandler.performApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.userJourneyHistory,
        queryParameters: queryParams,
      ),
      (data) => data,
    );
  }

  /// Get journey analytics by ID
  Future<Map<String, dynamic>> getJourneyAnalytics(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyAnalytics(journeyId),
      ),
      (data) => data,
    );
  }
}