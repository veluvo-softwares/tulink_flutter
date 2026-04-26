import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/mapbox_search_datasource.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';

class JourneyProvider extends ChangeNotifier {
  final CreateJourney createJourneyUseCase;
  final GetJourneyById getJourneyByIdUseCase;
  final GetActiveJourneys getActiveJourneysUseCase;
  final StartJourney startJourneyUseCase;
  final UpdateJourney updateJourneyUseCase;
  final EndJourney endJourneyUseCase;
  final MapboxSearchDataSource mapboxSearchDataSource;

  JourneyProvider({
    required this.createJourneyUseCase,
    required this.getJourneyByIdUseCase,
    required this.getActiveJourneysUseCase,
    required this.startJourneyUseCase,
    required this.updateJourneyUseCase,
    required this.endJourneyUseCase,
    required this.mapboxSearchDataSource,
  });

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Journey? _currentJourney;
  Journey? get currentJourney => _currentJourney;

  List<Journey> _activeJourneys = [];
  List<Journey> get activeJourneys => _activeJourneys;

  List<MapboxSearchResult> _searchResults = [];
  List<MapboxSearchResult> get searchResults => _searchResults;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  Future<bool> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    required String destinationAddress,
    required int lagThresholdMeters,
  }) async {
    _setLoading(true);
    _setError(null);

    final result = await createJourneyUseCase(
      name: name,
      latitude: latitude,
      longitude: longitude,
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
    );

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  Future<void> fetchActiveJourneys() async {
    _setLoading(true);
    _setError(null);

    final result = await getActiveJourneysUseCase();

    if (result.isSuccess && result.data != null) {
      _activeJourneys = result.data!;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
    }

    _setLoading(false);
  }

  Future<void> fetchJourneyById(String journeyId) async {
    _setLoading(true);
    _setError(null);

    final result = await getJourneyByIdUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
    }

    _setLoading(false);
  }

  Future<bool> startJourney(String journeyId) async {
    _setLoading(true);
    _setError(null);

    final result = await startJourneyUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateJourney({
    required String journeyId,
    required Map<String, dynamic> updateData,
  }) async {
    _setLoading(true);
    _setError(null);

    final result = await updateJourneyUseCase(
      journeyId: journeyId,
      updateData: updateData,
    );

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }

  Future<void> searchLocations(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _searchResults = await mapboxSearchDataSource.search(query);
    notifyListeners();
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  /// Set the current journey (used for continuing active journeys)
  void setCurrentJourney(Journey journey) {
    _currentJourney = journey;
    notifyListeners();
  }

  /// End a journey
    Future<bool> endJourney(String journeyId) async {
    _setLoading(true);
    _setError(null);

    final result = await endJourneyUseCase(journeyId);

    if (result.isSuccess && result.data != null) {
      _currentJourney = result.data;
      _setLoading(false);
      return true;
    } else {
      _setError(result.failure?.message ?? 'Unknown error');
      _setLoading(false);
      return false;
    }
  }
}
