import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/mapbox_search_datasource.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';
import 'package:tulink_flutter/features/navigation/domain/repositories/navigation_repository.dart';
import 'package:tulink_flutter/features/navigation/domain/entities/directions_route.dart';
import 'package:tulink_flutter/features/navigation/data/models/navigation_step.dart';

class JourneyProvider extends ChangeNotifier {
  final CreateJourney createJourneyUseCase;
  final GetJourneyById getJourneyByIdUseCase;
  final GetActiveJourneys getActiveJourneysUseCase;
  final StartJourney startJourneyUseCase;
  final UpdateJourney updateJourneyUseCase;
  final EndJourney endJourneyUseCase;
  final MapboxSearchDataSource mapboxSearchDataSource;
  final NavigationRepository navigationRepository;

  JourneyProvider({
    required this.createJourneyUseCase,
    required this.getJourneyByIdUseCase,
    required this.getActiveJourneysUseCase,
    required this.startJourneyUseCase,
    required this.updateJourneyUseCase,
    required this.endJourneyUseCase,
    required this.mapboxSearchDataSource,
    required this.navigationRepository,
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

  // Navigation-related state
  DirectionsRoute? _currentRoute;
  DirectionsRoute? get currentRoute => _currentRoute;

  List<DirectionsRoute> _routeAlternatives = [];
  List<DirectionsRoute> get routeAlternatives => _routeAlternatives;

  bool _isCalculatingRoute = false;
  bool get isCalculatingRoute => _isCalculatingRoute;

  String? _routeError;
  String? get routeError => _routeError;

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

  // Navigation Methods

  /// Calculate route for current journey
  Future<void> calculateRouteForJourney({
    geo.Position? currentPosition,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
    bool includeAlternatives = true,
  }) async {
    if (_currentJourney == null) {
      _setRouteError('No active journey to calculate route for');
      return;
    }

    _setCalculatingRoute(true);
    _setRouteError(null);

    try {
      // Get current position if not provided
      geo.Position? position = currentPosition;
      if (position == null) {
        try {
          position = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
          print('📱 Got current position: lat=${position.latitude}, lng=${position.longitude}');
        } catch (e) {
          print('❌ Failed to get current location: $e');
          _setRouteError('Could not get current location: $e');
          _setCalculatingRoute(false);
          return;
        }
      } else {
        print('📱 Using provided position: lat=${position.latitude}, lng=${position.longitude}');
      }

      print('🚗 Calculating route from current position to ${_currentJourney!.destinationAddress}');
      print('📍 Origin: lat=${position.latitude}, lng=${position.longitude}');
      print('🎯 Destination: lat=${_currentJourney!.destination.latitude}, lng=${_currentJourney!.destination.longitude}');

      if (includeAlternatives) {
        // Get route alternatives
        final alternativesResult = await navigationRepository.getRouteAlternatives(
          origin: LatLng(latitude: position.latitude, longitude: position.longitude),
          destination: _currentJourney!.destination,
          profile: profile,
        );

        if (alternativesResult.isSuccess && alternativesResult.data != null) {
          _routeAlternatives = alternativesResult.data!;
          if (_routeAlternatives.isNotEmpty) {
            _currentRoute = _routeAlternatives.first; // Set primary route
            await _updateJourneyWithRoute(_currentRoute!);
          }
        } else {
          _setRouteError(alternativesResult.failure?.message ?? 'Failed to calculate route alternatives');
        }
      } else {
        // Get single optimal route
        final routeResult = await navigationRepository.calculateRoute(
          origin: LatLng(latitude: position.latitude, longitude: position.longitude),
          destination: _currentJourney!.destination,
          profile: profile,
        );

        if (routeResult.isSuccess && routeResult.data != null) {
          _currentRoute = routeResult.data;
          _routeAlternatives = [_currentRoute!];
          await _updateJourneyWithRoute(_currentRoute!);
        } else {
          _setRouteError(routeResult.failure?.message ?? 'Failed to calculate route');
        }
      }
    } catch (e) {
      _setRouteError('Unexpected error calculating route: $e');
    }

    _setCalculatingRoute(false);
  }

  /// Select an alternative route
  Future<void> selectAlternativeRoute(DirectionsRoute route) async {
    _currentRoute = route;
    
    if (_currentJourney != null) {
      await _updateJourneyWithRoute(route);
    }
    
    notifyListeners();
  }

  /// Recalculate route (e.g., for rerouting)
  Future<void> recalculateRoute({
    geo.Position? currentPosition,
    bool forceUpdate = false,
  }) async {
    // Only recalculate if we have a current journey and route is stale or forced
    if (_currentJourney == null) return;
    
    final hasRoute = _currentJourney!.hasRoute;
    final routeAge = hasRoute && _currentJourney!.routeCalculatedAt != null
        ? DateTime.now().difference(_currentJourney!.routeCalculatedAt!)
        : null;
    
    // Recalculate if forced, no route exists, or route is older than 5 minutes
    if (forceUpdate || !hasRoute || (routeAge != null && routeAge.inMinutes > 5)) {
      await calculateRouteForJourney(
        currentPosition: currentPosition,
        includeAlternatives: false, // Don't need alternatives for recalculation
      );
    }
  }

  /// Get updated ETA for current route and position
  Future<Duration?> getUpdatedETA(geo.Position currentPosition) async {
    if (_currentRoute == null || _currentJourney == null) return null;

    try {
      final etaResult = await navigationRepository.getUpdatedETA(
        route: _currentRoute!,
        currentPosition: currentPosition,
        destination: _currentJourney!.destination,
      );

      if (etaResult.isSuccess && etaResult.data != null) {
        return etaResult.data;
      }
    } catch (e) {
      print('❌ Failed to get updated ETA: $e');
    }

    return null;
  }

  /// Clear route data
  void clearRoute() {
    _currentRoute = null;
    _routeAlternatives.clear();
    _setRouteError(null);
    
    // Update journey to remove route data
    if (_currentJourney != null) {
      _currentJourney = _currentJourney!.copyWithRoute(
        routeGeometry: null,
        estimatedDuration: null,
        estimatedDistance: null,
        routeCalculatedAt: null,
        navigationSteps: null,
      );
    }
    
    notifyListeners();
  }

  /// Update journey entity with route information
  Future<void> _updateJourneyWithRoute(DirectionsRoute route) async {
    if (_currentJourney == null) return;

    // Convert NavigationSteps to NavigationStepData
    final stepData = route.steps
        .map((step) => NavigationStepData(
              instruction: step.instruction,
              distance: step.distance,
              duration: step.duration,
              maneuverType: step.maneuver.type,
              maneuverModifier: step.maneuver.modifier,
              streetName: step.name,
            ))
        .toList();

    // Update current journey with route data
    _currentJourney = _currentJourney!.copyWithRoute(
      routeGeometry: route.geometry,
      estimatedDuration: route.duration,
      estimatedDistance: route.distance,
      routeCalculatedAt: DateTime.now(),
      navigationSteps: stepData,
    );

    notifyListeners();
  }

  // Route-related setters

  void _setCalculatingRoute(bool value) {
    _isCalculatingRoute = value;
    notifyListeners();
  }

  void _setRouteError(String? value) {
    _routeError = value;
    notifyListeners();
  }

  void clearRouteError() {
    _setRouteError(null);
  }
}
