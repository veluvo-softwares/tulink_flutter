import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../../../core/common/result.dart';
import '../../domain/entities/place_search_result.dart';
import '../../domain/entities/race_route.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/usecases/search_places_usecase.dart';
import '../../data/datasources/route_remote_data_source.dart';
import '../../data/models/route_result_model.dart';

class MapProvider with ChangeNotifier {
  final MapRepository _repository;
  final SearchPlacesUseCase _searchPlacesUseCase;
  final RouteRemoteDataSource _routeDataSource;

  MapProvider(
    this._repository,
    this._searchPlacesUseCase,
    this._routeDataSource,
  );

  RouteResultModel? _currentRoute;
  RouteResultModel? get currentRoute => _currentRoute;

  Future<RouteResultModel?> fetchRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final result = await _routeDataSource.getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    _currentRoute = result;
    notifyListeners();
    return result;
  }

  void clearRoute() {
    _currentRoute = null;
    notifyListeners();
  }

  RaceRoute? _marathonRoute;
  bool _isLoading = false;
  String? _error;
  
  List<PlaceSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  RaceRoute? get marathonRoute => _marathonRoute;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<PlaceSearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  Future<void> loadMarathonData() async {
    // Marathon data is deprecated
    _marathonRoute = null;
    notifyListeners();
  }
  
  Future<void> searchPlaces(String query) async {
    final trimmedQuery = query.trim();
    
    // Clear results if query is empty or too short
    if (trimmedQuery.isEmpty || trimmedQuery.length < 2) {
      _searchResults = [];
      _searchError = null;
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    // Acquire current position for location bias — fail silently
    geo.Position? pos;
    try {
      pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.low, // Low accuracy is fine for bias
        ),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // No coordinates — search still works, just unbiased
    }

    final result = await _searchPlacesUseCase(
      trimmedQuery,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );

    _isSearching = false;
    
    if (result.isSuccess && result.data != null) {
      _searchResults = result.data!;
      _searchError = null;
    } else if (result.isFailure && result.failure != null) {
      _searchResults = [];
      _searchError = result.failure!.message;
    }
    
    notifyListeners();
  }
  
  void clearSearchResults() {
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }
}
