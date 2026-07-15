import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';
import '../models/journey_summary_model.dart';
import '../services/analytics_api_service.dart';

/// Remote data source for analytics
/// Focuses purely on executing service calls and mapping results to Domain Entities
/// Zero hardcoded strings - all endpoints are defined in AnalyticsApiService
abstract class AnalyticsRemoteDataSource {
  /// Get recent journeys with optional limit

  /// Get user journey history with pagination
  Future<List<JourneyModel>> getJourneyHistory({int limit = 20});

  /// Get analytics for a specific journey
  Future<JourneyModel> getJourneyAnalytics(String journeyId);

  /// Get summary statistics for a specific journey
  Future<JourneySummaryModel?> getJourneySummary(String journeyId);
}

/// Implementation of AnalyticsRemoteDataSource using AnalyticsApiService
/// Pure data mapping layer with no business logic
/// Single responsibility: Execute API calls and map responses to domain entities
class AnalyticsRemoteDataSourceImpl implements AnalyticsRemoteDataSource {
  final AnalyticsApiService _analyticsApiService;

  AnalyticsRemoteDataSourceImpl(this._analyticsApiService);

  @override
  Future<List<JourneyModel>> getJourneyHistory({int limit = 20}) async {
    print('📡 Fetching journey history from API with limit: $limit');

    // Execute API call using standardized response
    final responseData = await _analyticsApiService.getUserJourneyHistory(
      limit: limit,
    );

    // responseData IS the data (ApiHandler.performStandardApiCall already extracted it)
    // Handle if the response is directly a list or has a 'data' field
    List<dynamic> journeysData;

    if (responseData is List) {
      journeysData = responseData as List<dynamic>;
    } else if (responseData is Map<String, dynamic> &&
        responseData.containsKey('data')) {
      final data = responseData['data'];
      if (data is List) {
        journeysData = data as List<dynamic>;
      } else {
        print('❌ Data field is not a list: ${data.runtimeType}');
        return [];
      }
    } else {
      print('❌ Response is neither List nor Map with data field');
      return [];
    }

    print('✅ Parsed ${journeysData.length} journey items from history API');

    return journeysData
        .map((json) => JourneyModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<JourneyModel> getJourneyAnalytics(String journeyId) async {
    // Execute API call using standardized response
    final responseData = await _analyticsApiService.getJourneyAnalytics(
      journeyId,
    );

    // responseData IS the data (ApiHandler already extracted it from response.data)
    return JourneyModel.fromJson(responseData);
  }

  @override
  Future<JourneySummaryModel?> getJourneySummary(String journeyId) async {
    try {
      final responseData = await _analyticsApiService.getJourneySummary(
        journeyId,
      );
      return JourneySummaryModel.fromJson(responseData);
    } catch (e) {
      print('⚠️ Failed to fetch journey summary: $e');
      return null;
    }
  }
}
