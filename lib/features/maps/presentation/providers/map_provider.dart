import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../../../core/common/result.dart';
import '../../../../core/constants/map_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/services/region_service.dart';
import '../../domain/entities/place_search_result.dart';
import '../../domain/entities/race_route.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/usecases/search_places_usecase.dart';
import '../../data/models/route_result_model.dart';

class MapProvider with ChangeNotifier {
  final MapRepository _repository;
  final SearchPlacesUseCase _searchPlacesUseCase;

  MapProvider(this._repository, this._searchPlacesUseCase);

  RouteResultModel? _currentRoute;
  String? _currentRouteJourneyId;
  RouteResultModel? get currentRoute => _currentRoute;

  bool _isFetchingRoute = false;
  bool get isFetchingRoute => _isFetchingRoute;

  Future<RouteResultModel?> fetchRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _isFetchingRoute = true;
    notifyListeners();

    // Draw the stored route first so a resumed journey has a line on the map
    // straight away. Routes are keyed by journey and validated against the
    // destination, so a hit is the same road the driver was already following;
    // the live fetch below still replaces it once it returns.
    await _drawCachedRoute(
      userId: userId,
      journeyId: journeyId,
      destLat: destLat,
      destLng: destLng,
    );

    try {
      final result = await _repository.getRoute(
        userId: userId,
        journeyId: journeyId,
        originLat: originLat,
        originLng: originLng,
        destinationLat: destLat,
        destinationLng: destLng,
      );
      if (result != null) {
        _currentRoute = result;
        _currentRouteJourneyId = journeyId;
        return result;
      }
      // A transient failure must not erase the route currently guiding this
      // same active journey.
      return _currentRouteJourneyId == journeyId ? _currentRoute : null;
    } finally {
      _isFetchingRoute = false;
      notifyListeners();
    }
  }

  /// Show the stored route for this journey, if one is held and nothing is
  /// already drawn for it.
  Future<void> _drawCachedRoute({
    required String userId,
    required String journeyId,
    required double destLat,
    required double destLng,
  }) async {
    if (_currentRouteJourneyId == journeyId && _currentRoute != null) return;

    try {
      final cached = await _repository.getCachedRoute(
        userId: userId,
        journeyId: journeyId,
        destinationLat: destLat,
        destinationLng: destLng,
      );
      if (cached == null) return;

      _currentRoute = cached;
      _currentRouteJourneyId = journeyId;
      notifyListeners();
    } catch (e) {
      // Cache trouble must never block the live fetch.
      print('⚠️ Could not read cached route: $e');
    }
  }

  void clearRoute() {
    _currentRoute = null;
    _currentRouteJourneyId = null;
    notifyListeners();
  }

  RaceRoute? _marathonRoute;
  bool _isLoading = false;
  String? _error;

  List<PlaceSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  /// Monotonic id tagging each search; a response whose id is no longer the
  /// latest is discarded so a slow/stale out-of-order response never overwrites
  /// newer or cleared state. Incremented on every search and on clear.
  int _searchRequestId = 0;

  RaceRoute? get marathonRoute => _marathonRoute;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<PlaceSearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  // The location-bias coordinate used for the most recent search (live →
  // last-known → Nairobi default). Exposed so the search UI can flag results
  // that are implausibly far from the user. Never null after a search runs.
  double? _searchBiasLat;
  double? _searchBiasLng;

  /// Latitude of the bias point used for the most recent search, or null if
  /// no search has run yet.
  double? get searchBiasLat => _searchBiasLat;

  /// Longitude of the bias point used for the most recent search, or null if
  /// no search has run yet.
  double? get searchBiasLng => _searchBiasLng;

  Future<void> loadMarathonData() async {
    // Marathon data is deprecated
    _marathonRoute = null;
    notifyListeners();
  }

  Future<void> searchPlaces(String query) async {
    final trimmedQuery = query.trim();

    // Tag this search; any later state mutation is guarded against this id so a
    // stale/out-of-order response is dropped instead of clobbering newer state.
    final requestId = ++_searchRequestId;

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

    // Resolve a location-bias coordinate so the query is never sent unbiased:
    // live fix → last-known position → Nairobi default. Logged by source only
    // (never coordinates) to preserve privacy.
    final bias = await _resolveSearchBias();
    _searchBiasLat = bias.latitude;
    _searchBiasLng = bias.longitude;

    // Derive the search region from the same bias fix (cached per session,
    // refreshed only on significant movement). Null when unresolved, in which
    // case the param is omitted and the backend default applies.
    final regionCode = await RegionService.resolveRegionCode(
      lat: bias.latitude,
      lng: bias.longitude,
    );

    final result = await _searchPlacesUseCase(
      trimmedQuery,
      lat: bias.latitude,
      lng: bias.longitude,
      regionCode: regionCode,
    );

    // Superseded by a newer search (or a clear) while this one was in flight —
    // discard silently so stale results never overwrite current state.
    if (requestId != _searchRequestId) return;

    // A cancelled/aborted request is benign — never surface an error card.
    final failure = result.failure;
    if (failure is SearchFailure && failure.isCancellation) {
      _isSearching = false;
      notifyListeners();
      return;
    }

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

  /// Resolve a location-bias coordinate for place search, trying in order:
  /// a live low-accuracy fix (short timeout) → the last-known position →
  /// [kDefaultMapCenter]. Always returns a coordinate so a search is never
  /// sent unbiased. Logs only which source was used, never the coordinates.
  Future<MapCoordinate> _resolveSearchBias() async {
    // 1. Live fix — low accuracy is fine for biasing; short timeout so a cold
    //    GPS doesn't stall the search.
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 3));
      print('✅ bias: live');
      return MapCoordinate(latitude: pos.latitude, longitude: pos.longitude);
    } catch (_) {
      // Fall through to last-known.
    }

    // 2. Last-known position — instant, no fix wait.
    try {
      final lastKnown = await geo.Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        print('✅ bias: last-known');
        return MapCoordinate(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
        );
      }
    } catch (_) {
      // Fall through to default.
    }

    // 3. Default centre (Nairobi).
    print('✅ bias: default');
    return kDefaultMapCenter;
  }

  void clearSearchResults() {
    // Invalidate any in-flight search so its late response is dropped.
    _searchRequestId++;
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }
}
