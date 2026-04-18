import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tulink_flutter/core/utils/logger.dart';
import 'package:tulink_flutter/features/analytics/domain/usecases/analytics_usecases.dart';
import '../../../journeys/domain/entities/journey.dart';


class AnalyticsProvider extends ChangeNotifier {
  final GetRecentJourneysUseCase _getRecentJourneysUseCase;
  final GetJourneyHistoryUseCase _getJourneyHistoryUseCase;
  final GetJourneyAnalyticsUseCase _getJourneyAnalyticsUseCase;

  AnalyticsProvider(
    this._getRecentJourneysUseCase,
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


  /// Load recent journeys (limited to 5 for home screen)
  Future<void> loadRecentJourneys({int limit = 5}) async {
    _setLoading(true);
    _clearError();

    final result = await _getRecentJourneysUseCase(limit: limit);
    
    if (result.data != null) {
      _recentJourneys = result.data!;
    } else {
      _setError(result.failure?.message ?? 'Failed to load recent journeys');
      _recentJourneys = [];
    }

    _setLoading(false);
  }

  /// Load complete journey history (for history screen)
  Future<void> loadJourneyHistory({int limit = 100}) async {
    _setLoading(true);
    _clearError();

    try {
      final result = await _getJourneyHistoryUseCase(limit: limit);

      if (result.data != null) {
        _journeyHistory = result.data!;
      } else {
        final errorMessage = result.failure?.message ?? 'Failed to load journey history';
        _setError(errorMessage);
        _journeyHistory = [];
      }
    } catch (e) {
      _setError('Failed to load journey history: $e');
      _journeyHistory = [];
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