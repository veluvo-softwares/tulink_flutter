import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';
import '../services/analytics_api_service.dart';

/// Remote data source for analytics
/// Focuses purely on executing service calls and mapping results to Domain Entities
/// Zero hardcoded strings - all endpoints are defined in AnalyticsApiService
abstract class AnalyticsRemoteDataSource {
  /// Get recent journeys with optional limit
  Future<List<JourneyModel>> getRecentJourneys({int? limit});

  /// Get user journey history with pagination
  Future<List<JourneyModel>> getJourneyHistory({int limit = 20});

  /// Get analytics for a specific journey
  Future<JourneyModel> getJourneyAnalytics(String journeyId);
}

/// Implementation of AnalyticsRemoteDataSource using AnalyticsApiService
/// Pure data mapping layer with no business logic
/// Single responsibility: Execute API calls and map responses to domain entities
class AnalyticsRemoteDataSourceImpl implements AnalyticsRemoteDataSource {
  final AnalyticsApiService _analyticsApiService;

  AnalyticsRemoteDataSourceImpl(this._analyticsApiService);

  @override
  Future<List<JourneyModel>> getRecentJourneys({int? limit}) async {
    // Execute API call through service - this now uses standardized response
    final responseData = await _analyticsApiService.getUserAnalytics(limit: limit);
    
    // Since API service returns Map<String, dynamic>, check for 'data' field
    List<dynamic> journeysData;
    if (responseData.containsKey('data')) {
      final data = responseData['data'];
      if (data is List) {
        journeysData = data;
      } else {
        return [];
      }
    } else {
      return [];
    }
    
    return journeysData
        .map((json) => JourneyModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<JourneyModel>> getJourneyHistory({int limit = 20}) async {
    // Execute API call using standardized response
    final responseData = await _analyticsApiService.getUserJourneyHistory(limit: limit);
    
    // Since API service returns Map<String, dynamic>, check for 'data' field
    List<dynamic> journeysData;
    if (responseData.containsKey('data')) {
      final data = responseData['data'];
      if (data is List) {
        journeysData = data;
      } else {
        return [];
      }
    } else {
      return [];
    }
    
    return journeysData
        .map((json) => JourneyModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<JourneyModel> getJourneyAnalytics(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _analyticsApiService.getJourneyAnalytics(journeyId);
    
    // responseData IS the data (ApiHandler already extracted it from response.data)
    return JourneyModel.fromJson(responseData);
  }
}