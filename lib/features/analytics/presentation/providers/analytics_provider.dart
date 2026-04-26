import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tulink_flutter/core/utils/logger.dart';
import 'package:tulink_flutter/features/analytics/domain/usecases/analytics_usecases.dart';
import '../../../journeys/domain/entities/journey.dart';


class AnalyticsProvider extends ChangeNotifier {
  final GetJourneyHistoryUseCase _getJourneyHistoryUseCase;
  final GetJourneyAnalyticsUseCase _getJourneyAnalyticsUseCase;

  AnalyticsProvider(
    this._getJourneyHistoryUseCase,
    this._getJourneyAnalyticsUseCase,
  );

  // State
  List<Journey> _recentJourneys = [];
  List<Journey> _journeyHistory = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<Journey> get recentJourneys => _recentJourneys;
  List<Journey> get journeyHistory => _journeyHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;


  /// Load recent journeys (derived from journey history, limited to 4 for home screen)
  /// Excludes active journeys and shows only completed/cancelled/paused journeys
  Future<void> loadRecentJourneys({int limit = 4}) async {
    print('🔄 Loading recent journeys (derived from journey history) with limit: $limit');
    
    // If we already have journey history loaded, derive from it
    if (_journeyHistory.isNotEmpty) {
      _deriveRecentJourneysFromHistory(limit);
      return;
    }

    // Otherwise, load journey history first, then derive recent journeys
    _setLoading(true);
    _clearError();

    try {
      final result = await _getJourneyHistoryUseCase(limit: 100); // Get larger set to filter from
      
      if (result.data != null) {
        _journeyHistory = result.data!;
        print('✅ Loaded ${_journeyHistory.length} journey history items for recent journeys derivation');
        
        // Derive recent journeys from the loaded history
        _deriveRecentJourneysFromHistory(limit);
      } else {
        final errorMsg = result.failure?.message ?? 'Failed to load recent journeys';
        print('❌ Failed to load recent journeys: $errorMsg');
        _setError(errorMsg);
        _recentJourneys = [];
      }
    } catch (e) {
      print('❌ Exception loading recent journeys: $e');
      _setError('Failed to load recent journeys: $e');
      _recentJourneys = [];
    }

    _setLoading(false);
  }

  /// Derive recent journeys from existing journey history
  /// Filters out active journeys and takes the first [limit] items
  void _deriveRecentJourneysFromHistory(int limit) {
    _recentJourneys = _journeyHistory
        .where((journey) => journey.status != JourneyStatus.ACTIVE)
        .take(limit)
        .toList();
    
    print('✅ Derived ${_recentJourneys.length} recent journeys from ${_journeyHistory.length} total journeys (excluding active)');
    notifyListeners();
  }

  /// Load complete journey history (for history screen)
  /// Also automatically derives recent journeys from the loaded data
  Future<void> loadJourneyHistory({int limit = 20}) async {
    print('🔄 Loading journey history with limit: $limit');
    _setLoading(true);
    _clearError();

    try {
      final result = await _getJourneyHistoryUseCase(limit: limit);

      if (result.data != null) {
        _journeyHistory = result.data!;
        print('✅ Loaded ${_journeyHistory.length} journey history items');
        
        // Automatically derive recent journeys from the loaded history
        _deriveRecentJourneysFromHistory(4);
      } else {
        final errorMessage = result.failure?.message ?? 'Failed to load journey history';
        print('❌ Failed to load journey history: $errorMessage');
        _setError(errorMessage);
        _journeyHistory = [];
        _recentJourneys = []; // Clear recent journeys too
      }
    } catch (e) {
      print('❌ Exception loading journey history: $e');
      _setError('Failed to load journey history: $e');
      _journeyHistory = [];
      _recentJourneys = []; // Clear recent journeys too
    }

    _setLoading(false);
  }

  /// Get journey analytics by ID
  Future<Journey?> getJourneyAnalytics(String journeyId) async {
    final result = await _getJourneyAnalyticsUseCase(journeyId);
    
    if (result.data != null) {
      return result.data;
    } else {
      _setError(result.failure?.message ?? 'Failed to load journey analytics');
      return null;
    }
  }

  /// Refresh recent journeys
  Future<void> refreshRecentJourneys() async {
    await loadRecentJourneys();
  }

  /// Refresh journey history
  Future<void> refreshJourneyHistory() async {
    await loadJourneyHistory();
  }

  /// Clear error message
  void clearError() {
    _clearError();
  }

  // Private methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}