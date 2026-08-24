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

  /// Full identity of the route currently held, so a reader for a different
  /// user/journey/destination is never handed someone else's geometry.
  String? _currentRouteKey;

  /// The surface generation the held route was resolved under. A rebuilt
  /// surface has none of the drawn geometry, so work captured against the old
  /// generation must not be treated as current.
  int? _currentRouteSurfaceGeneration;

  /// The route currently held, regardless of who it belongs to.
  ///
  /// Prefer [routeFor]: this accessor cannot tell a caller whether the route
  /// is theirs, and returning another journey's (or another user's) geometry
  /// is exactly how a stale line survived onto the next journey.
  RouteResultModel? get currentRoute => _currentRoute;

  /// The held route, but only when it matches the caller's full identity.
  ///
  /// Returns null when the held route belongs to a different user/session,
  /// journey, destination, or map surface generation.
  RouteResultModel? routeFor({
    required String userId,
    required String journeyId,
    required double destLat,
    required double destLng,
    int? surfaceGeneration,
  }) {
    final key = _routeKey(
      userId: userId,
      journeyId: journeyId,
      destLat: destLat,
      destLng: destLng,
    );
    if (_currentRouteKey != key) return null;
    if (surfaceGeneration != null &&
        _currentRouteSurfaceGeneration != null &&
        _currentRouteSurfaceGeneration != surfaceGeneration) {
      return null;
    }
    return _currentRoute;
  }

  bool _isFetchingRoute = false;
  bool get isFetchingRoute => _isFetchingRoute;

  /// Monotonic request token. Every route request captures the value it was
  /// issued under; only the newest may mutate route state or clear the loading
  /// flag. Without this a slow request for journey A could land after B and
  /// overwrite B's route, or clear loading while B was still fetching.
  int _routeRequestSeq = 0;

  /// The token of the request whose result is currently authoritative.
  int _latestRouteRequest = 0;

  /// Identity of the newest in-flight request, so a stale result can be
  /// rejected even if tokens are equal across a session change.
  String? _latestRouteKey;

  /// Generation of the map surface the newest request was issued against.
  int _surfaceGeneration = 0;

  /// The map surface generation route work is currently valid for.
  int get surfaceGeneration => _surfaceGeneration;

  /// Request identity: user/session + journey + destination. A change in any of
  /// them makes an in-flight response stale.
  static String _routeKey({
    required String userId,
    required String journeyId,
    required double destLat,
    required double destLng,
  }) =>
      '$userId|$journeyId|${destLat.toStringAsFixed(6)}|'
      '${destLng.toStringAsFixed(6)}';

  /// Abandon any in-flight route request, e.g. on draft clear or journey
  /// switch. The held route is deliberately kept: an active journey's line
  /// must survive a draft being cleared out from under it.
  void invalidateRouteRequests() {
    _latestRouteRequest = ++_routeRequestSeq;
    _latestRouteKey = null;
    if (_isFetchingRoute) {
      _isFetchingRoute = false;
      notifyListeners();
    }
  }

  /// The shared map surface was rebuilt.
  ///
  /// Everything captured against the previous generation drew onto a style
  /// that no longer exists, so it is invalidated wholesale. The held route is
  /// retained so the layer that owns the new surface can redraw it, but it is
  /// re-stamped with the new generation only when a matching request lands.
  void onSurfaceGenerationChanged(int generation) {
    if (_surfaceGeneration == generation) return;
    _surfaceGeneration = generation;
    invalidateRouteRequests();
  }

  /// The signed-in user changed (login, logout, account switch).
  ///
  /// A route is scoped to the user who requested it, so anything held for a
  /// different session is dropped rather than being shown to the new one.
  void onUserChanged(String? userId) {
    invalidateRouteRequests();
    final held = _currentRouteKey;
    if (held == null) return;
    if (userId != null && held.startsWith('$userId|')) return;
    _currentRoute = null;
    _currentRouteKey = null;
    _currentRouteSurfaceGeneration = null;
    notifyListeners();
  }

  Future<RouteResultModel?> fetchRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    int? surfaceGeneration,
  }) async {
    final token = ++_routeRequestSeq;
    final key = _routeKey(
      userId: userId,
      journeyId: journeyId,
      destLat: destLat,
      destLng: destLng,
    );
    final surface = surfaceGeneration ?? _surfaceGeneration;
    _latestRouteRequest = token;
    _latestRouteKey = key;

    /// True while this request is still the newest one issued *and* the map
    /// surface it was issued against is still the one on screen.
    ///
    /// Cached and network results are held to exactly this one predicate. They
    /// used to differ: the cache path wrote unconditionally, so a slow cache
    /// lookup for A overwrote B's freshly fetched route even though the
    /// network path was guarded.
    bool isCurrent() =>
        _latestRouteRequest == token &&
        _latestRouteKey == key &&
        _surfaceGeneration == surface;

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
      key: key,
      surface: surface,
      isCurrent: isCurrent,
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
        // A superseded request must not overwrite the newer destination's
        // route, and must not become what the map draws.
        if (!isCurrent()) return null;
        _install(result, key, surface);
        return result;
      }
      if (!isCurrent()) return null;
      // A transient failure must not erase the route currently guiding this
      // same active journey — but only if the held route really is this
      // journey's, for this user, to this destination.
      return _currentRouteKey == key ? _currentRoute : null;
    } finally {
      // Only the newest request owns the loading flag; an older one finishing
      // must not signal "done" while the current request is still running.
      if (isCurrent()) {
        _isFetchingRoute = false;
        notifyListeners();
      }
    }
  }

  void _install(RouteResultModel route, String key, int surface) {
    _currentRoute = route;
    _currentRouteKey = key;
    _currentRouteSurfaceGeneration = surface;
  }

  /// Show the stored route for this request, if one is held and nothing is
  /// already drawn for it.
  ///
  /// Obeys the *same* [isCurrent] predicate as the network path. A cache read
  /// is asynchronous, so it can land after a newer request has taken over; it
  /// used to install unconditionally and clobber the newer route.
  Future<void> _drawCachedRoute({
    required String userId,
    required String journeyId,
    required double destLat,
    required double destLng,
    required String key,
    required int surface,
    required bool Function() isCurrent,
  }) async {
    if (_currentRouteKey == key && _currentRoute != null) return;

    try {
      final cached = await _repository.getCachedRoute(
        userId: userId,
        journeyId: journeyId,
        destinationLat: destLat,
        destinationLng: destLng,
      );
      if (cached == null) return;
      // Superseded while the cache was being read.
      if (!isCurrent()) return;

      _install(cached, key, surface);
      notifyListeners();
    } catch (e) {
      // Cache trouble must never block the live fetch.
      print('⚠️ Could not read cached route: $e');
    }
  }

  void clearRoute() {
    _currentRoute = null;
    _currentRouteKey = null;
    _currentRouteSurfaceGeneration = null;
    // A cleared route must also abandon whatever is still in flight for it,
    // or that response lands a moment later and undoes the clear.
    invalidateRouteRequests();
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
