import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tulink_flutter/features/analytics/domain/usecases/analytics_usecases.dart';
import '../../../../core/errors/user_facing_error.dart';
import '../../data/models/journey_summary_model.dart';
import '../../../journeys/domain/entities/journey.dart';

class AnalyticsProvider extends ChangeNotifier {
  final GetJourneyHistoryUseCase _getJourneyHistoryUseCase;
  final GetJourneyAnalyticsUseCase _getJourneyAnalyticsUseCase;
  final GetJourneySummaryUseCase _getJourneySummaryUseCase;

  /// Optional so existing construction sites keep working; without it the
  /// provider simply has nothing to paint before the network answers.
  final GetCachedJourneyHistoryUseCase? _getCachedJourneyHistoryUseCase;

  AnalyticsProvider(
    this._getJourneyHistoryUseCase,
    this._getJourneyAnalyticsUseCase,
    this._getJourneySummaryUseCase, [
    this._getCachedJourneyHistoryUseCase,
  ]);

  // State
  List<Journey> _recentJourneys = [];
  List<Journey> _journeyHistory = [];
  bool _isLoading = false;
  String? _error;

  JourneySummaryModel? _currentSummary;
  bool _isSummaryLoading = false;
  String? _summaryError;

  // Getters
  List<Journey> get recentJourneys => _recentJourneys;
  List<Journey> get journeyHistory => _journeyHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;

  JourneySummaryModel? get currentSummary => _currentSummary;
  bool get isSummaryLoading => _isSummaryLoading;
  String? get summaryError => _summaryError;

  /// Load summary statistics for a completed journey
  Future<void> loadJourneySummary(String journeyId) async {
    _isSummaryLoading = true;
    _summaryError = null;
    notifyListeners();

    final result = await _getJourneySummaryUseCase(journeyId);
    if (result.data != null) {
      _currentSummary = result.data;
    } else {
      _currentSummary = null;
      _summaryError = userFacingErrorMessage(result.failure);
      print(
        '⚠️ Failed to load journey summary: '
        '${result.failure?.message ?? 'unknown error'}',
      );
    }

    _isSummaryLoading = false;
    notifyListeners();
  }

  /// Load recent journeys (derived from journey history, limited to 4 for home screen)
  /// Excludes active journeys and shows only completed/cancelled/paused journeys
  Future<void> loadRecentJourneys({int limit = 4}) async {
    print(
      '🔄 Loading recent journeys (derived from journey history) with limit: $limit',
    );

    // If we already have journey history loaded, derive from it
    if (_journeyHistory.isNotEmpty) {
      _deriveRecentJourneysFromHistory(limit);
      return;
    }

    // Otherwise, load journey history first, then derive recent journeys
    _setLoading(true);
    _clearError();

    try {
      final result = await _getJourneyHistoryUseCase(
        limit: 100,
      ); // Get larger set to filter from

      if (result.data != null) {
        _journeyHistory = result.data!;
        print(
          '✅ Loaded ${_journeyHistory.length} journey history items for recent journeys derivation',
        );

        // Derive recent journeys from the loaded history
        _deriveRecentJourneysFromHistory(limit);
      } else {
        final errorMsg = userFacingErrorMessage(result.failure);
        print('❌ Failed to load recent journeys: $errorMsg');
        _setError(errorMsg);
        _recentJourneys = [];
      }
    } catch (e) {
      print('❌ Exception loading recent journeys: $e');
      _setError(userFacingErrorMessage(e));
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

    print(
      '✅ Derived ${_recentJourneys.length} recent journeys from ${_journeyHistory.length} total journeys (excluding active)',
    );
    notifyListeners();
  }

  /// Load complete journey history (for history screen)
  /// Also automatically derives recent journeys from the loaded data
  Future<void> loadJourneyHistory({int limit = 20}) async {
    print('🔄 Loading journey history with limit: $limit');
    _setLoading(true);
    _clearError();

    // Paint what the device already knows before waiting on the network.
    // A finished journey never changes, so cached history is not "stale" in
    // any way that matters — it is simply the past. Without this the list
    // renders its empty state on every cold start and only fills in once the
    // request returns, which reads as "you have no journeys" to a returning
    // driver.
    final hadCache = await _hydrateHistoryFromCache();

    try {
      final result = await _getJourneyHistoryUseCase(limit: limit);

      if (result.data != null) {
        _journeyHistory = result.data!;
        print('✅ Loaded ${_journeyHistory.length} journey history items');

        // Automatically derive recent journeys from the loaded history
        _deriveRecentJourneysFromHistory(4);
      } else {
        final errorMessage = userFacingErrorMessage(result.failure);
        print('❌ Failed to load journey history: $errorMessage');
        _setError(errorMessage);
        // Keep whatever was hydrated: the fetch failing says nothing about
        // whether those journeys happened. Blanking the list here would turn
        // a dropped request into "your history is gone".
        if (!hadCache) {
          _journeyHistory = [];
          _recentJourneys = [];
        }
      }
    } catch (e) {
      print('❌ Exception loading journey history: $e');
      _setError(userFacingErrorMessage(e));
      if (!hadCache) {
        _journeyHistory = [];
        _recentJourneys = [];
      }
    }

    _setLoading(false);
  }

  /// Fill the list from disk and paint. Returns whether anything was found.
  Future<bool> _hydrateHistoryFromCache() async {
    final useCase = _getCachedJourneyHistoryUseCase;
    if (useCase == null || _journeyHistory.isNotEmpty) return false;

    try {
      final cached = await useCase();
      if (cached.isEmpty) return false;

      _journeyHistory = cached;
      _deriveRecentJourneysFromHistory(4);
      print('💾 Painted ${cached.length} journeys from cache');
      notifyListeners();
      return true;
    } catch (e) {
      // Cache trouble must never block the live fetch.
      print('⚠️ Could not read cached journey history: $e');
      return false;
    }
  }

  /// Get journey analytics by ID
  Future<Journey?> getJourneyAnalytics(String journeyId) async {
    final result = await _getJourneyAnalyticsUseCase(journeyId);

    if (result.data != null) {
      return result.data;
    } else {
      _setError(userFacingErrorMessage(result.failure));
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
