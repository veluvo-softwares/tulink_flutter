import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/tulink_colors.dart';
import '../data/models/route_result_model.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'providers/map_provider.dart';
import 'services/convoy_interpolation_service.dart';
import '../../journeys/presentation/providers/journey_provider.dart';
import '../../journeys/domain/entities/journey.dart';
import '../../convoy/presentation/providers/convoy_provider.dart';
import '../../convoy/presentation/widgets/convoy_status_bar.dart';
import '../../convoy/presentation/widgets/convoy_bottom_sheet.dart';
import '../../convoy/presentation/widgets/convoy_metrics_bottom_sheet.dart';
import '../../convoy/presentation/widgets/journey_progress_card.dart';
import '../../convoy/presentation/widgets/driver_marker.dart';
import '../../convoy/presentation/widgets/convoy_route_line.dart';
import '../../convoy/presentation/services/journey_status_notifier.dart';
import '../../convoy/presentation/utils/convoy_member_presentation.dart';
import '../../convoy/domain/entities/convoy_snapshot.dart';
import '../../convoy/domain/entities/member_position.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../analytics/presentation/screens/journey_details_screen.dart';
import 'widgets/map_journey_overlay.dart';
import 'widgets/map_header_overlay.dart';
import 'widgets/turn_instruction_card.dart';
import 'providers/navigation_provider.dart';
import '../domain/entities/route_progress.dart';
import 'utils/route_rendering.dart';

class TulinkMapScreen extends StatefulWidget {
  const TulinkMapScreen({super.key});

  static const String routeName = '/mapview';

  @override
  State<TulinkMapScreen> createState() => _TulinkMapScreenState();
}

class _TulinkMapScreenState extends State<TulinkMapScreen>
    with WidgetsBindingObserver {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  String? _activeJourneyId;
  bool _isConvoyCoordinationActive = false;
  ConvoySnapshot? _lastSnapshot;
  int _lastUpdateHash = 0;
  bool _disposed = false;
  bool _isAppActive = true;
  int _mapGeneration = 0;

  /// True when it's safe to call the Mapbox channel — set false on dispose
  /// so async chains that resume after the widget is unmounted bail out
  /// instead of throwing PlatformException on a dead channel.
  bool get _canUseMap =>
      !_disposed && _isAppActive && mounted && _mapboxMap != null;

  /// Coalesces duplicate route setup calls from map creation and convoy
  /// startup. Both lifecycle paths run during the same navigation transition.
  Future<void>? _routeSetupFuture;
  String? _routeSetupJourneyId;

  // Follow by default, but yield permanently to an explicit user pan until
  // they tap recenter. This lets drivers inspect the road ahead or the wider
  // convoy without the next GPS update snapping the camera back.
  bool _cameraFollowEnabled = true;
  StreamSubscription<geo.Position>? _cameraFollowSubscription;

  // Cached provider reference — safe to call in dispose() without a context.
  NavigationProvider? _navigationProvider;

  // Cached convoy provider + user id so the interpolation ticker can pull
  // fresh peer positions without reading context from a Timer callback.
  ConvoyProvider? _convoyProvider;
  String? _convoyUserId;
  Map<String, ConvoyMemberPresentation> _memberPresentation = const {};

  // Drives smooth, interpolated peer-marker movement between broadcast
  // snapshots. Mapbox does not tween between discrete source updates, so this
  // ticker pushes display-only projected positions to the marker source in
  // place (~12.5 Hz). Cancelled in dispose and whenever there are no peers.
  Timer? _interpolationTicker;
  bool _interpolationRenderInFlight = false;
  final ConvoyMotionSmoother _peerMotionSmoother = ConvoyMotionSmoother();

  // True once the backend confirms the current user has arrived at the
  // destination (via `participant-arrived` WebSocket event).  Stops the
  // navigation layer and shows the arrival confirmation overlay.
  bool _currentUserHasArrived = false;

  // Progress card is collapsed by default so the map is visible while driving.
  // The user taps the pill to expand it when they need stats or the end button.
  bool _isProgressCardExpanded = false;
  bool _isJourneyExitInProgress = false;

  /// True while a programmatic camera animation is in flight.
  bool _isProgrammaticCameraMove = false;

  /// Last time we wrote to the polyline source. Throttles subsequent writes
  /// to at most one per 400 ms — the JSON encode + platform channel hop is
  /// expensive enough that doing it every GPS tick causes visible jitter.
  DateTime? _lastTrimAt;

  /// Last time we wrote to the snapped puck source. Higher update rate
  /// than the polyline (200 ms) because puck responsiveness is more
  /// perceptually important.
  DateTime? _lastPuckUpdateAt;
  Future<void>? _rawPuckRenderFuture;

  // Eases the local, route-snapped puck between GNSS fixes. The route leading
  // edge is rendered from the same coordinate so the line never detaches.
  Timer? _navigationFrameTicker;
  RouteProgress? _navigationTarget;
  DateTime? _navigationAnimationStartedAt;
  double? _navigationStartLatitude;
  double? _navigationStartLongitude;
  double? _displayedNavigationLatitude;
  double? _displayedNavigationLongitude;
  int? _displayedNavigationSegmentIndex;
  bool _navigationFrameRenderInFlight = false;

  /// Android background journey-status notification (per-member distances).
  final JourneyStatusNotifier _statusNotifier = JourneyStatusNotifier();

  /// Tracks the built-in Mapbox location puck's enabled state.
  /// `null` = unknown (nothing applied yet). The custom snapped puck owns the
  /// screen during navigation, so we keep the built-in puck off while a
  /// journey is active — otherwise both render and you see the red + blue
  /// double-marker. See [_setBuiltInPuckEnabled].
  bool? _puckEnabled;
  geo.Position? _lastRawPuckPosition;
  bool _rawPuckRemovedForNavigation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _isAppActive = false;
      return;
    }

    if (state != AppLifecycleState.resumed || _isAppActive || !mounted) return;

    // Recreate the native Mapbox view after a real background transition.
    // On some devices the platform surface resumes black even though Flutter
    // and the overlays continue rendering. A new keyed MapWidget gets a fresh
    // surface; _onMapCreated restores route, destination, markers and camera.
    _isAppActive = true;

    // The server heartbeat monitor evicts the socket while we're suspended
    // (Dart timers freeze, so no heartbeats go out). Bring it back up now
    // with a fresh token instead of waiting for the next publish to fail.
    unawaited(context.read<ConvoyProvider>().onAppResumed());
    _mapboxMap = null;
    _pointAnnotationManager = null;
    _lastUpdateHash = 0;
    _puckEnabled = null;
    _rawPuckRemovedForNavigation = false;
    _lastTrimAt = null;
    setState(() => _mapGeneration++);
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();

    // Enable user location with defensive guards
    await _enableUserLocation(mapboxMap);

    // Draw static journey data immediately — does not wait for any WebSocket
    // snapshot to arrive. The destination is journey data, not convoy data.
    if (mounted) {
      final currentJourney = context.read<JourneyProvider>().currentJourney;
      if (currentJourney != null &&
          currentJourney.status == JourneyStatus.ACTIVE) {
        await _drawDestinationPin(currentJourney);
        await _fitCameraToJourney(currentJourney);
        // Let the camera animation settle before the loading pill appears
        await Future<void>.delayed(const Duration(milliseconds: 400));
        // Fetch the real road route — loading state shown via HUD indicator
        unawaited(_drawActualRoute(currentJourney));

        // Auto-transition from overview to driving mode 2.5 s after the route
        // draw starts. Fires even when the device is stationary so the user
        // is never stuck in the zoomed-out overview waiting for the GPS
        // stream's first 10 m tick.
        Future<void>.delayed(const Duration(milliseconds: 2500), () async {
          if (!_canUseMap || !_cameraFollowEnabled) return;

          geo.Position? pos;
          try {
            pos = await geo.Geolocator.getCurrentPosition(
              locationSettings: const geo.LocationSettings(
                accuracy: geo.LocationAccuracy.high,
              ),
            ).timeout(const Duration(seconds: 5));
          } catch (_) {
            return; // GPS not ready — leave the overview in place
          }

          if (!_canUseMap) return;

          _isProgrammaticCameraMove = true;
          try {
            await _mapboxMap!.setCamera(
              CameraOptions(
                center: Point(
                  coordinates: Position(pos.longitude, pos.latitude),
                ),
                bearing: pos.heading,
                zoom: 16.0,
                pitch: 45.0,
              ),
            );
          } finally {
            _isProgrammaticCameraMove = false;
          }
        });
      }
    }

    await _updateMarkers();
    _checkAndStartConvoyCoordination();
  }

  /// Draw the destination pin from static [Journey] data.
  /// Independent of any [ConvoySnapshot] — the destination is fixed journey
  /// data and is available the moment the map is created.
  Future<void> _drawDestinationPin(Journey journey) async {
    if (_mapboxMap == null) return;
    const sourceId = 'journey-destination-source';
    const ringId = 'journey-destination-ring';
    const dotId = 'journey-destination-dot';

    try {
      await _mapboxMap!.style.removeStyleLayer(ringId);
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleLayer(dotId);
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleSource(sourceId);
    } catch (_) {}

    try {
      final geoJson = jsonEncode({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'Point',
          'coordinates': [
            journey.destination.longitude,
            journey.destination.latitude,
          ],
        },
      });

      await _mapboxMap!.style.addSource(
        GeoJsonSource(id: sourceId, data: geoJson),
      );

      // Outer pulse ring — Electric Red at 20% opacity
      await _mapboxMap!.style.addLayer(
        CircleLayer(
          id: ringId,
          sourceId: sourceId,
          circleRadius: 16.0,
          circleColor: 0x33E8002D,
          circleStrokeColor: 0xFFE8002D,
          circleStrokeWidth: 2.5,
          circleOpacity: 1.0,
        ),
      );

      // Inner solid dot
      await _mapboxMap!.style.addLayer(
        CircleLayer(
          id: dotId,
          sourceId: sourceId,
          circleRadius: 8.0,
          circleColor: 0xFFE8002D,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2.0,
          circleOpacity: 1.0,
        ),
      );

      print(
        '✅ Destination pin drawn at '
        '${journey.destination.latitude}, ${journey.destination.longitude}',
      );
    } catch (e) {
      print('⚠️ Failed to draw destination pin: $e');
    }
  }

  /// Fit the camera to show both the user's current position and the journey
  /// destination. Falls back to centering on the destination if GPS or the
  /// bounds calculation is unavailable.
  Future<void> _fitCameraToJourney(Journey journey) async {
    if (_mapboxMap == null) return;

    geo.Position? pos;
    try {
      pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
    } catch (e) {
      print(
        '⚠️ Could not get position for camera fit — centering on destination',
      );
      _isProgrammaticCameraMove = true;
      try {
        await _mapboxMap!.setCamera(
          CameraOptions(
            center: Point(
              coordinates: Position(
                journey.destination.longitude,
                journey.destination.latitude,
              ),
            ),
            zoom: 13.0,
          ),
        );
      } finally {
        _isProgrammaticCameraMove = false;
      }
      return;
    }

    // Build bounding box from user position + destination
    final minLng = pos.longitude < journey.destination.longitude
        ? pos.longitude
        : journey.destination.longitude;
    final maxLng = pos.longitude > journey.destination.longitude
        ? pos.longitude
        : journey.destination.longitude;
    final minLat = pos.latitude < journey.destination.latitude
        ? pos.latitude
        : journey.destination.latitude;
    final maxLat = pos.latitude > journey.destination.latitude
        ? pos.latitude
        : journey.destination.latitude;

    try {
      final camera = await _mapboxMap!.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(minLng, minLat)),
          northeast: Point(coordinates: Position(maxLng, maxLat)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 140.0, left: 60.0, bottom: 260.0, right: 60.0),
        null,
        null,
        null,
        null,
      );
      _isProgrammaticCameraMove = true;
      try {
        await _mapboxMap!.setCamera(camera);
      } finally {
        _isProgrammaticCameraMove = false;
      }
      print('✅ Camera fitted to journey bounds');
    } catch (e) {
      print(
        '⚠️ cameraForCoordinateBounds failed: $e — falling back to destination center',
      );
      _isProgrammaticCameraMove = true;
      try {
        await _mapboxMap!.setCamera(
          CameraOptions(
            center: Point(
              coordinates: Position(
                journey.destination.longitude,
                journey.destination.latitude,
              ),
            ),
            zoom: 13.0,
          ),
        );
      } finally {
        _isProgrammaticCameraMove = false;
      }
    }
  }

  /// Fetch the road-following route from the backend and draw it on the map.
  /// Fails silently — the destination pin stays visible without a route line.
  Future<void> _drawActualRoute(
    Journey journey, {
    double? knownLat,
    double? knownLng,
  }) {
    final inFlight = _routeSetupFuture;
    if (inFlight != null && _routeSetupJourneyId == journey.id) {
      return inFlight;
    }

    final future = _drawActualRouteInternal(
      journey,
      knownLat: knownLat,
      knownLng: knownLng,
    );
    _routeSetupJourneyId = journey.id;
    _routeSetupFuture = future;
    return future.whenComplete(() {
      if (identical(_routeSetupFuture, future)) {
        _routeSetupFuture = null;
        _routeSetupJourneyId = null;
      }
    });
  }

  Future<void> _drawActualRouteInternal(
    Journey journey, {
    double? knownLat,
    double? knownLng,
  }) async {
    if (_mapboxMap == null) return;

    // Prefer a position already in hand (e.g. from the live navigation stream)
    // to avoid paying the GPS cold-start cost (up to 5s on Android) again.
    double? originLat = knownLat;
    double? originLng = knownLng;

    if (originLat == null || originLng == null) {
      geo.Position? pos;
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        print('⚠️ Could not get position for route: $e');
        return; // Keep the straight-line placeholder
      }
      originLat = pos.latitude;
      originLng = pos.longitude;
    }

    if (!mounted) return;
    final mapProvider = context.read<MapProvider>();

    // Use the prefetched route if it matches this destination — no network call.
    RouteResultModel? route = mapProvider.currentRoute;
    final isCachedForThisDestination =
        route != null &&
        route.coordinates.isNotEmpty &&
        _coordinatesMatch(
          route.coordinates.last,
          journey.destination.longitude,
          journey.destination.latitude,
        );

    if (isCachedForThisDestination) {
      print('✅ Using prefetched route — skipping fetch');
    } else {
      print('🌐 No prefetched route — fetching now');
      route = await mapProvider.fetchRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: journey.destination.latitude,
        destLng: journey.destination.longitude,
      );
    }

    if (route == null || !mounted || _mapboxMap == null) return;

    // Draw the actual road-following route
    const sourceId = 'actual-route-source';
    const bgId = 'actual-route-bg';
    const lineId = 'actual-route-line';

    try {
      await _mapboxMap!.style.removeStyleLayer(lineId);
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleLayer(bgId);
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleSource(sourceId);
    } catch (_) {}

    try {
      final geoJson = jsonEncode({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': route.coordinates, // [[lng,lat],...] from Mapbox
        },
      });

      await _mapboxMap!.style.addSource(
        GeoJsonSource(id: sourceId, data: geoJson),
      );

      // Shadow line for depth
      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: bgId,
          sourceId: sourceId,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidth: 8.0,
          lineColor: 0xFF000000,
          lineOpacity: 0.25,
        ),
      );

      // Electric Red solid route line (roads → solid, not dashed)
      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: lineId,
          sourceId: sourceId,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidth: 5.0,
          lineColor: 0xFFE8002D,
          lineOpacity: 0.9,
        ),
      );

      print(
        '✅ Actual road route drawn: '
        '${route.distanceMetres.toStringAsFixed(0)}m, '
        '${route.steps.length} steps',
      );
    } catch (e) {
      print('⚠️ Failed to draw actual route: $e');
    }

    // Hand the route to the navigation layer for turn-by-turn guidance.
    if (mounted) {
      final navigation = context.read<NavigationProvider>();
      if (navigation.activeRoute == route && navigation.isNavigating) return;
      await navigation.startNavigation(
        route: route,
        onRerouteNeeded: () => _handleReroute(journey),
      );
    }
  }

  /// Called by [NavigationProvider] when sustained off-route is detected.
  /// Fetches a fresh route from the user's current position to the journey
  /// destination and redraws the polyline. The `_drawActualRoute` call
  /// reuses the existing layer IDs, so the polyline replaces itself
  /// cleanly.
  Future<void> _handleReroute(Journey journey) async {
    if (!mounted) return;
    print('🧭 Handling reroute for journey ${journey.id}');

    // Grab the current position from the live navigation stream before clearing
    // state. When off-route, snappedLatitude/Longitude holds the raw GPS
    // coordinate (MapMatchingService returns raw when deviation > threshold),
    // so it is the correct origin for the new route — and it's already in hand,
    // avoiding a second GPS cold-start wait.
    final progress = context.read<NavigationProvider>().currentProgress;
    final knownLat = progress?.snappedLatitude;
    final knownLng = progress?.snappedLongitude;

    // Clear the cached route so _drawActualRoute fetches a fresh one.
    context.read<MapProvider>().clearRoute();
    // Reset throttle state so trim and puck start immediately on the new route.
    _lastTrimAt = null;

    await _drawActualRoute(journey, knownLat: knownLat, knownLng: knownLng);

    final newRoute = context.read<MapProvider>().currentRoute;
    print('🧭 reroute fetched: ${newRoute?.coordinates.length ?? 0} coords');
    if (newRoute != null && mounted) {
      context.read<NavigationProvider>().loadRoute(newRoute);
    }
  }

  /// True if a route's last coordinate is within ~110 m of the given target.
  /// Used to detect whether a cached route was generated for the current
  /// journey's destination. [coord] is [lng, lat].
  bool _coordinatesMatch(List<double> coord, double destLng, double destLat) {
    return (coord[0] - destLng).abs() < 0.001 &&
        (coord[1] - destLat).abs() < 0.001;
  }

  /// Snap the camera to the user's current GPS position and re-enable follow
  /// Animates the camera back to the device's current position and
  /// re-enables follow mode. Called by the recenter button after the user
  /// has panned away.
  Future<void> _recenterOnUser() async {
    if (_mapboxMap == null) return;
    geo.Position? pos;
    try {
      pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('⚠️ Recenter: could not get position: $e');
      return;
    }

    // Prefer snapped position when available, mirroring _updateCameraFollow.
    final progress = _navigationProvider?.currentProgress;
    final centerLat = progress?.snappedLatitude ?? pos.latitude;
    final centerLng = progress?.snappedLongitude ?? pos.longitude;

    _cameraFollowEnabled = true;
    _isProgrammaticCameraMove = true;
    try {
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          bearing: pos.heading,
          zoom: 16.0,
          pitch: 45.0,
        ),
        MapAnimationOptions(duration: 800),
      );
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  /// Track the user's current position with bearing and a 3D driving tilt.
  /// Centres on the snapped position when navigation is active so the camera
  /// matches the visible puck position on the route.
  Future<void> _updateCameraFollow(geo.Position position) async {
    if (_mapboxMap == null || !_cameraFollowEnabled) return;

    // Prefer snapped position when navigation is active so the camera centre
    // matches the custom puck. Falls back to raw GPS when navigation is
    // inactive or no progress snapshot exists yet.
    final progress = _navigationProvider?.currentProgress;
    _lastRawPuckPosition = position;
    if (progress == null) {
      unawaited(_drawRawPuck(position));
    }
    final centerLat = _displayedNavigationLatitude ??
        progress?.snappedLatitude ??
        position.latitude;
    final centerLng = _displayedNavigationLongitude ??
        progress?.snappedLongitude ??
        position.longitude;

    _isProgrammaticCameraMove = true;
    try {
      await _mapboxMap!.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          bearing: position.heading,
          zoom: 16.0,
          pitch: 45.0,
        ),
      );
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider reference here while the context is still active.
    // dispose() must not call context.read<>() on a deactivated element.
    final nav = context.read<NavigationProvider>();
    if (_navigationProvider != nav) {
      _navigationProvider?.removeListener(_onNavigationProgress);
      _navigationProvider = nav;
      _navigationProvider?.addListener(_onNavigationProgress);
    }
    // Refresh markers only when provider dependencies actually change,
    // rather than on every build().
    if (_mapboxMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateMarkers();
      });
    }
  }

  /// Called by [NavigationProvider] on every GPS tick while navigating.
  /// Trims the drawn route polyline so only the road ahead is visible.
  void _onNavigationProgress() {
    final progress = _navigationProvider?.currentProgress;
    if (progress != null && _canUseMap) {
      _navigationStartLatitude =
          _displayedNavigationLatitude ?? progress.snappedLatitude;
      _navigationStartLongitude =
          _displayedNavigationLongitude ?? progress.snappedLongitude;
      _displayedNavigationSegmentIndex ??= progress.currentSegmentIndex;
      _navigationTarget = progress;
      _navigationAnimationStartedAt = DateTime.now();
      _navigationFrameTicker ??= Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _renderNextNavigationFrame(),
      );
      _renderNextNavigationFrame();
    }
  }

  Future<void> _renderNextNavigationFrame() async {
    final target = _navigationTarget;
    final startedAt = _navigationAnimationStartedAt;
    final startLat = _navigationStartLatitude;
    final startLng = _navigationStartLongitude;
    if (!_canUseMap ||
        target == null ||
        startedAt == null ||
        startLat == null ||
        startLng == null ||
        _navigationFrameRenderInFlight) {
      return;
    }

    const animationDurationMs = 900;
    final linearT =
        DateTime.now()
            .difference(startedAt)
            .inMilliseconds
            .clamp(0, animationDurationMs) /
        animationDurationMs;
    final inverse = 1 - linearT;
    final easedT = 1 - (inverse * inverse * inverse);
    final route = _navigationProvider?.activeRoute;
    final rendered = route == null
        ? (
            longitude: startLng +
                (target.snappedLongitude - startLng) * easedT,
            latitude:
                startLat + (target.snappedLatitude - startLat) * easedT,
            segmentIndex: target.currentSegmentIndex,
          )
        : interpolateRoutePosition(
            routeCoordinates: route.coordinates,
            startLongitude: startLng,
            startLatitude: startLat,
            startSegmentIndex: _displayedNavigationSegmentIndex ??
                target.currentSegmentIndex,
            targetLongitude: target.snappedLongitude,
            targetLatitude: target.snappedLatitude,
            targetSegmentIndex: target.currentSegmentIndex,
            t: easedT,
          );
    final latitude = rendered.latitude;
    final longitude = rendered.longitude;
    _displayedNavigationLatitude = latitude;
    _displayedNavigationLongitude = longitude;
    _displayedNavigationSegmentIndex = rendered.segmentIndex;

    final frame = RouteProgress(
      currentManeuver: target.currentManeuver,
      distanceToNextManeuverMetres: target.distanceToNextManeuverMetres,
      distanceRemainingMetres: target.distanceRemainingMetres,
      durationRemainingSeconds: target.durationRemainingSeconds,
      snappedLatitude: latitude,
      snappedLongitude: longitude,
      isOffRoute: target.isOffRoute,
      currentSegmentIndex: rendered.segmentIndex,
    );

    _navigationFrameRenderInFlight = true;
    try {
      await _drawSnappedPuck(frame);
      await _trimRoutePolyline(frame);
    } finally {
      _navigationFrameRenderInFlight = false;
    }

    if (linearT >= 1 && identical(target, _navigationTarget)) {
      _navigationFrameTicker?.cancel();
      _navigationFrameTicker = null;
    }
  }

  /// Update the GeoJSON source for the route polyline to show only the
  /// coordinates from the driver's snapped position onward — the portion of
  /// the route the driver still has to cover.
  Future<void> _trimRoutePolyline(RouteProgress progress) async {
    if (!_canUseMap) return;
    const sourceId = 'actual-route-source';

    final route = _navigationProvider?.activeRoute;
    if (route == null || route.coordinates.length < 2) return;

    // The animation ticker drives this source; cap writes to a map-friendly
    // cadence while keeping the route head visually attached to the puck.
    final now = DateTime.now();
    if (_lastTrimAt != null &&
        now.difference(_lastTrimAt!).inMilliseconds < 160) {
      return;
    }

    final remaining = buildRemainingRouteCoordinates(
      routeCoordinates: route.coordinates,
      segmentIndex: progress.currentSegmentIndex,
      snappedLongitude: progress.snappedLongitude,
      snappedLatitude: progress.snappedLatitude,
    );
    if (remaining.length < 2) return;

    _lastTrimAt = now;

    print(
      '✂️ Trim to segIdx=${progress.currentSegmentIndex}, '
      'remaining=${remaining.length}/${route.coordinates.length}',
    );

    try {
      final geoJson = jsonEncode({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'LineString', 'coordinates': remaining},
      });
      await _mapboxMap!.style.setStyleSourceProperty(sourceId, 'data', geoJson);
    } catch (e) {
      print('⚠️ Trim polyline failed: $e');
    }
  }

  /// Draw a custom puck at the snapped (on-road) position from the
  /// navigation provider. Replaces Mapbox's built-in puck during active
  /// navigation so the visible position matches the planned route.
  ///
  /// When [progress] is null (navigation stopped) the puck layers are
  /// removed. When the source already exists subsequent calls only update
  /// the GeoJSON data — cheaper than re-adding layers on every tick.
  Future<void> _drawSnappedPuck(RouteProgress? progress) async {
    if (!_canUseMap) return;
    const sourceId = 'snapped-puck-source';
    const ringId = 'snapped-puck-ring';
    const dotId = 'snapped-puck-dot';

    if (progress == null) {
      try {
        await _mapboxMap!.style.removeStyleLayer(dotId);
      } catch (_) {}
      try {
        await _mapboxMap!.style.removeStyleLayer(ringId);
      } catch (_) {}
      try {
        await _mapboxMap!.style.removeStyleSource(sourceId);
      } catch (_) {}
      final rawPosition = _lastRawPuckPosition;
      _rawPuckRemovedForNavigation = false;
      if (rawPosition != null) await _drawRawPuck(rawPosition);
      return;
    }

    if (!_rawPuckRemovedForNavigation) {
      await _removeRawPuck();
      _rawPuckRemovedForNavigation = true;
    }

    // Match the local animation ticker without flooding the platform channel.
    final now = DateTime.now();
    if (_lastPuckUpdateAt != null &&
        now.difference(_lastPuckUpdateAt!).inMilliseconds < 80) {
      return;
    }
    _lastPuckUpdateAt = now;

    // Keep the built-in puck off for the entire life of the snapped puck.
    // Re-asserted on every (throttled) tick — but cheap: _setBuiltInPuckEnabled
    // short-circuits once the state is applied, so this is a no-op after the
    // first disable. A single failed disable can no longer leave the blue puck
    // stranded under the red one.
    await _setBuiltInPuckEnabled(false);

    final geoJson = jsonEncode({
      'type': 'Feature',
      'properties': <String, dynamic>{'color': _currentUserColorHex},
      'geometry': {
        'type': 'Point',
        'coordinates': [progress.snappedLongitude, progress.snappedLatitude],
      },
    });

    try {
      final sourceExists = await _mapboxMap!.style.styleSourceExists(sourceId);
      if (!sourceExists) {
        // Built-in puck is already disabled above; just add the snapped puck.
        await _mapboxMap!.style.addSource(
          GeoJsonSource(id: sourceId, data: geoJson),
        );

        // Red halo indicates that the position is snapped to the road route.
        await _mapboxMap!.style.addLayer(
          CircleLayer(
            id: ringId,
            sourceId: sourceId,
            circleRadius: 14.0,
            circleColorExpression: ['get', 'color'],
            circleOpacity: 0.45,
            circleStrokeWidth: 0,
          ),
        );

        // Inner solid dot — Electric Red, Tu-Link branded.
        await _mapboxMap!.style.addLayer(
          CircleLayer(
            id: dotId,
            sourceId: sourceId,
            circleRadius: 7.0,
            circleColorExpression: ['get', 'color'],
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 2.5,
            circleOpacity: 1.0,
          ),
        );
      } else {
        // Update geometry only — avoids recreating the layers on every tick.
        await _mapboxMap!.style.setStyleSourceProperty(
          sourceId,
          'data',
          geoJson,
        );
      }
    } catch (e) {
      print('⚠️ Failed to draw snapped puck: $e');
    }
  }

  /// Render TuLink's red self-marker at the raw GPS position while route
  /// snapping is not ready. The white halo distinguishes acquisition/raw GPS
  /// from the red-halo snapped navigation state without changing identity.
  Future<void> _drawRawPuck(geo.Position position) async {
    if (!_canUseMap || _navigationProvider?.currentProgress != null) return;
    final inFlight = _rawPuckRenderFuture;
    if (inFlight != null) return inFlight;

    final render = _renderRawPuck(position);
    _rawPuckRenderFuture = render;
    try {
      await render;
    } finally {
      if (identical(_rawPuckRenderFuture, render)) {
        _rawPuckRenderFuture = null;
      }
    }
  }

  Future<void> _renderRawPuck(geo.Position position) async {
    const sourceId = 'raw-puck-source';
    const ringId = 'raw-puck-ring';
    const dotId = 'raw-puck-dot';

    await _setBuiltInPuckEnabled(false);
    final geoJson = jsonEncode({
      'type': 'Feature',
      'properties': <String, dynamic>{'color': _currentUserColorHex},
      'geometry': {
        'type': 'Point',
        'coordinates': [position.longitude, position.latitude],
      },
    });

    try {
      final exists = await _mapboxMap!.style.styleSourceExists(sourceId);
      if (!exists) {
        await _mapboxMap!.style.addSource(
          GeoJsonSource(id: sourceId, data: geoJson),
        );
        await _mapboxMap!.style.addLayer(
          CircleLayer(
            id: ringId,
            sourceId: sourceId,
            circleRadius: 14,
            circleColor: 0xFFFFFFFF,
            circleOpacity: 0.65,
            circleStrokeWidth: 0,
          ),
        );
        await _mapboxMap!.style.addLayer(
          CircleLayer(
            id: dotId,
            sourceId: sourceId,
            circleRadius: 7,
            circleColorExpression: ['get', 'color'],
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 2.5,
            circleOpacity: 1,
          ),
        );
      } else {
        await _mapboxMap!.style.setStyleSourceProperty(
          sourceId,
          'data',
          geoJson,
        );
      }
    } catch (e) {
      print('⚠️ Failed to draw raw TuLink puck: $e');
    }
  }

  Future<void> _removeRawPuck() async {
    if (!_canUseMap) return;
    // Navigation can become ready while the initial raw-puck source is still
    // being created. Wait for that mutation before removing it so create and
    // remove cannot cross and leave either a duplicate source or a stale puck.
    final pendingRender = _rawPuckRenderFuture;
    if (pendingRender != null) {
      try {
        await pendingRender;
      } catch (_) {}
    }
    try {
      await _mapboxMap!.style.removeStyleLayer('raw-puck-dot');
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleLayer('raw-puck-ring');
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleSource('raw-puck-source');
    } catch (_) {}
  }

  /// Set Mapbox's built-in location puck on/off, tracking the applied state so
  /// we never spam the platform channel and so navigation can cheaply
  /// re-assert "off" on every tick. Errors are logged, not swallowed — a
  /// silent failure here is precisely what let the blue built-in puck leak
  /// through alongside the red snapped puck (the double-marker bug).
  Future<void> _setBuiltInPuckEnabled(bool enabled) async {
    if (!_canUseMap) return;
    // Already in the desired state — skip the redundant channel hop.
    if (_puckEnabled == enabled) return;
    try {
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: enabled,
          pulsingEnabled: enabled,
          puckBearingEnabled: enabled,
          puckBearing: PuckBearing.HEADING,
        ),
      );
      _puckEnabled = enabled;
    } catch (e) {
      print('⚠️ Failed to set built-in puck enabled=$enabled: $e');
    }
  }

  /// Enable user location with proper permission and auth checks
  Future<void> _enableUserLocation(MapboxMap mapboxMap) async {
    try {
      // Check if user is authenticated
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.user;

      if (currentUser == null) {
        print('⚠️ User not authenticated, skipping user location');
        return;
      }

      await _setBuiltInPuckEnabled(false);
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      _lastRawPuckPosition = position;
      await _drawRawPuck(position);
      print('✅ User location component enabled for ${currentUser.id}');
    } catch (e) {
      print('❌ Failed to enable user location: $e');
      // Continue without user location rather than crashing
    }
  }

  Future<void> _updateMarkers() async {
    if (!_canUseMap) return;

    // Get convoy snapshot and current user
    final convoyProvider = context.read<ConvoyProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.id;
    final currentName = authProvider.user?.name;

    // Cache for the interpolation ticker, which runs outside the widget tree.
    _convoyProvider = convoyProvider;
    _convoyUserId = currentUserId;

    final journey = context.read<JourneyProvider>().currentJourney;
    if (journey != null) {
      _memberPresentation = ConvoyMemberPresentation.forJourney(
        journey,
        additionalUserIds: convoyProvider.snapshot?.members.keys ?? const [],
        currentUserId: currentUserId,
        currentUserName: currentName,
      );
    }

    // Get convoy snapshot filtered to exclude current user
    final convoySnapshot = currentUserId != null
        ? convoyProvider.getDisplaySnapshot(currentUserId)
        : convoyProvider.snapshot;

    final hasPeers =
        convoySnapshot != null &&
        currentUserId != null &&
        convoySnapshot.members.isNotEmpty &&
        !(convoySnapshot.destination.latitude == 0.0 &&
            convoySnapshot.destination.longitude == 0.0);

    // Generate a hash to check if the snapshot has actually changed
    final currentHash = _generateSnapshotHash(convoySnapshot);

    // Membership / colour / destination changes gate the (in-place) source
    // create + teardown. Smooth position movement between snapshots is driven
    // by the interpolation ticker, not this hash.
    if (currentHash != _lastUpdateHash) {
      _lastUpdateHash = currentHash;
      _lastSnapshot = convoySnapshot;

      if (hasPeers) {
        await ConvoyRouteLine.addConvoyMarkers(
          _mapboxMap!,
          convoySnapshot,
          currentUserId,
          _memberPresentation,
        );
        print(
          '✅ Updated convoy markers: ${convoySnapshot.members.length} members',
        );
      } else {
        await ConvoyRouteLine.removeConvoyMarkers(_mapboxMap!);
        print('✅ Removed convoy visualization');
        _lastSnapshot = null;
      }
    }

    // Run the smooth-movement ticker only while there are peers to animate.
    if (hasPeers) {
      _startInterpolationTicker();
    } else {
      _stopInterpolationTicker();
    }

    // Refresh the background journey-status surface (Android notification /
    // iOS Live Activity). The notifier throttles internally, so per-snapshot
    // calls are cheap.
    if (journey != null && currentUserId != null) {
      unawaited(
        _statusNotifier.update(
          journeyName: journey.name,
          selfUserId: currentUserId,
          presentation: _memberPresentation,
          snapshot: convoySnapshot,
          progress: _navigationProvider?.currentProgress,
        ),
      );
    }
  }

  /// Start the periodic ticker that pushes interpolated peer positions to the
  /// in-place marker source. Idempotent — safe to call on every snapshot.
  void _startInterpolationTicker() {
    if (_interpolationTicker != null) return;
    _interpolationTicker = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _onInterpolationTick(),
    );
  }

  /// Stop the interpolation ticker — no peers, coordination stopped, dispose.
  void _stopInterpolationTicker() {
    _interpolationTicker?.cancel();
    _interpolationTicker = null;
    _interpolationRenderInFlight = false;
    _peerMotionSmoother.clear();
  }

  /// One render tick: recompute display-only interpolated coordinates for all
  /// peers and push them to the marker source in place. Never mutates the
  /// snapshot or provider — the authoritative position is the last received
  /// MemberPosition.
  Future<void> _onInterpolationTick() async {
    if (!_canUseMap) {
      _stopInterpolationTicker();
      return;
    }
    // Skip this tick if the previous in-place render is still in flight.
    if (_interpolationRenderInFlight) return;

    final provider = _convoyProvider;
    final userId = _convoyUserId;
    if (provider == null || userId == null) return;

    final snapshot = provider.getDisplaySnapshot(userId);
    final members = snapshot?.members.values.toList() ?? <MemberPosition>[];
    if (members.isEmpty) {
      _stopInterpolationTicker();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final coordinates = <List<double>>[
      for (final member in members)
        _peerMotionSmoother.positionFor(member, now),
    ];
    _peerMotionSmoother.retainUsers(members.map((member) => member.userId));

    _interpolationRenderInFlight = true;
    try {
      await ConvoyRouteLine.renderMemberMarkers(
        _mapboxMap!,
        members,
        coordinates,
        _memberPresentation,
      );
    } finally {
      _interpolationRenderInFlight = false;
    }
  }

  String get _currentUserColorHex {
    final color =
        _memberPresentation[_convoyUserId]?.color ??
        ConvoyMemberPresentation.palette.first;
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Generate a simple hash of the convoy snapshot for change detection
  int _generateSnapshotHash(ConvoySnapshot? snapshot) {
    if (snapshot == null) return 0;

    int hash = 0;
    hash ^= snapshot.members.length.hashCode;
    hash ^= snapshot.destination.latitude.hashCode;
    hash ^= snapshot.destination.longitude.hashCode;

    // Include member positions in hash
    for (final member in snapshot.members.values) {
      hash ^= member.latitude.hashCode;
      hash ^= member.longitude.hashCode;
      hash ^= member.timestamp.hashCode;
      hash ^= (member.isMoving ? 1 : 0).hashCode;
    }

    return hash;
  }

  /// Check if convoy coordination should be started
  void _checkAndStartConvoyCoordination() {
    if (!mounted) return;
    final journeyProvider = context.read<JourneyProvider>();
    final convoyProvider = context.read<ConvoyProvider>();
    final currentJourney = journeyProvider.currentJourney;

    // Start convoy coordination if there's an active journey
    if (currentJourney != null &&
        currentJourney.status == JourneyStatus.ACTIVE &&
        !_isConvoyCoordinationActive) {
      _activeJourneyId = currentJourney.id;
      _isConvoyCoordinationActive = true;

      // Note: do NOT disable the built-in puck here. It stays on until the
      // snapped puck actually starts drawing (see _drawSnappedPuck), otherwise
      // the user has no puck during the journey overview / pre-driving window.

      // Start convoy coordination
      convoyProvider.startCoordination(currentJourney.id);

      // Ensure the destination pin and route are drawn from static journey
      // data even when the map screen is reached without _onMapCreated firing.
      if (_mapboxMap != null) {
        _drawDestinationPin(currentJourney);
        _drawActualRoute(currentJourney);
      }

      // Track the user's position so the camera follows during driving.
      // This is a separate stream from ConvoyProvider's publishing stream.
      _cameraFollowSubscription ??=
          geo.Geolocator.getPositionStream(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              distanceFilter: 10, // Update camera every 10m
            ),
          ).listen((position) {
            _updateCameraFollow(position);
          });
    }
  }

  /// Stop convoy coordination when leaving the map
  void _stopConvoyCoordination() {
    if (_isConvoyCoordinationActive) {
      final convoyProvider = context.read<ConvoyProvider>();
      convoyProvider.stopCoordination();
      _isConvoyCoordinationActive = false;
      _activeJourneyId = null;
    }
  }

  /// Show convoy bottom sheet with member list
  void _showConvoyBottomSheet() {
    final convoyProvider = context.read<ConvoyProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.id;

    // For bottom sheet member list, show filtered snapshot (others only)
    final snapshot = currentUserId != null
        ? convoyProvider.getDisplaySnapshot(currentUserId)
        : convoyProvider.getFullSnapshot();

    if (snapshot != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ConvoyBottomSheet(
          snapshot: snapshot,
          onMemberTap: (member) {
            Navigator.pop(context);
            unawaited(_focusOnMember(member));
          },
          onClose: () => Navigator.pop(context),
        ),
      );
    }
  }

  /// Move the camera to a selected convoy member and leave follow mode off so
  /// subsequent local GPS updates do not immediately pull the map away.
  Future<void> _focusOnMember(MemberPosition member) async {
    if (!_canUseMap) return;
    _cameraFollowEnabled = false;
    _isProgrammaticCameraMove = true;
    try {
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(member.longitude, member.latitude),
          ),
          zoom: 16.0,
          pitch: 35.0,
        ),
        MapAnimationOptions(duration: 700),
      );
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  /// Show convoy management options
  void _showConvoyManagementOptions() {
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();
    final currentJourney = journeyProvider.currentJourney;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentJourney != null &&
                currentJourney.inviteCode != null &&
                currentJourney.leaderId ==
                    context.read<AuthProvider>().user?.id)
              ListTile(
                leading: const Icon(Icons.ios_share, color: Colors.green),
                title: const Text(
                  'Share Journey Code',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  currentJourney.inviteCode!,
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () async {
                  final code = currentJourney.inviteCode!;
                  final journeyName = currentJourney.name;
                  final box = context.findRenderObject() as RenderBox?;
                  final origin = box == null
                      ? const Rect.fromLTWH(0, 0, 1, 1)
                      : box.localToGlobal(Offset.zero) & box.size;
                  Navigator.pop(context);
                  await SharePlus.instance.share(
                    ShareParams(
                      subject: 'Join my TuLink convoy',
                      text:
                          'Join "$journeyName" on TuLink. Open the app, tap Join a journey, and enter code $code.',
                      sharePositionOrigin: origin,
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.blue),
              title: const Text(
                'Refresh Convoy Data',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                if (currentJourney != null) {
                  convoyProvider.refreshSnapshot(currentJourney.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshing convoy data...')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.wifi_off, color: Colors.orange),
              title: const Text(
                'Reconnect to Convoy',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                if (currentJourney != null) {
                  convoyProvider.stopCoordination().then((_) {
                    convoyProvider.startCoordination(currentJourney.id);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reconnecting to convoy...')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: const Text(
                'Clear Error',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                convoyProvider.clearError();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop, color: Colors.red),
              title: const Text(
                'End Journey',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _showEndJourneyConfirmation();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// End the journey and stop convoy coordination.
  ///
  /// Captures the journey ID before any async work because providers can clear
  /// [JourneyProvider.currentJourney] mid-flight (e.g. the home screen's
  /// polling timer sees the journey gone from the server's active list).
  /// If the API call fails because the backend already completed the journey,
  /// we still navigate home rather than leaving the user stranded on the map.
  Future<void> _endJourney() async {
    if (_isJourneyExitInProgress) return;
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();

    // Capture before any await — providers may clear this during the async gap.
    final journeyId = journeyProvider.currentJourney?.id ?? _activeJourneyId;

    if (journeyId == null) {
      // Journey already cleared externally — just navigate home cleanly.
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
      return;
    }

    setState(() => _isJourneyExitInProgress = true);
    final success = await journeyProvider.endJourney(journeyId);

    if (!context.mounted) return;

    if (success) {
      await _navigationProvider?.stopNavigation();
      await convoyProvider.stopCoordination();
      if (!mounted) return;
      final completedJourney = journeyProvider.lastCompletedJourney;
      journeyProvider.consumeLastCompletedJourney();

      if (completedJourney != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => JourneyDetailsScreen(
              journey: completedJourney,
              showDoneButton: true,
            ),
          ),
        );
      } else {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } else {
      setState(() => _isJourneyExitInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(journeyProvider.error ?? 'Could not end journey'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _leaveJourney() async {
    if (_isJourneyExitInProgress) return;
    final journeyProvider = context.read<JourneyProvider>();
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyId = journeyProvider.currentJourney?.id ?? _activeJourneyId;
    if (journeyId == null) return;

    setState(() => _isJourneyExitInProgress = true);
    final success = await journeyProvider.leaveJourney(journeyId);
    if (!mounted) return;

    if (!success) {
      setState(() => _isJourneyExitInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(journeyProvider.error ?? 'Could not leave journey'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _navigationProvider?.stopNavigation();
    await convoyProvider.stopCoordination();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  /// Handles a `participant-arrived` WebSocket event.
  ///
  /// When the backend confirms the *current user* has reached the destination
  /// (geofence: 100 m + speed < 5 km/h), this stops turn-by-turn navigation
  /// and switches the screen into "arrived" mode.  Other participants' arrivals
  /// only update the shared arrival counter — no local state change needed.
  void _handleArrivalEvent() {
    if (!mounted) return;
    final convoyProvider = context.read<ConvoyProvider>();
    final event = convoyProvider.lastArrivalEvent;
    if (event == null) return;

    final currentUserId = context.read<AuthProvider>().user?.id;

    if (event.userId == currentUserId && !_currentUserHasArrived) {
      setState(() => _currentUserHasArrived = true);
      // Stop turn-by-turn once the user is confirmed at the destination.
      _navigationProvider?.stopNavigation();
    }

    // Consume so subsequent rebuilds don't re-trigger this block.
    convoyProvider.consumeArrivalEvent();
  }

  /// Handles a server-driven `journey-ended` event received while the map
  /// screen is active (e.g. the leader ended from another device, or the
  /// backend auto-completed after all participants arrived).
  ///
  /// Called from the build post-frame callback so it runs after the widget
  /// tree has settled and navigation is safe.
  void _handleJourneyEndedEvent() {
    if (!mounted || _isJourneyExitInProgress) return;
    final convoyProvider = context.read<ConvoyProvider>();
    final event = convoyProvider.lastJourneyEndedEvent;
    if (event == null) return;

    // Consume up-front so a rebuild triggered by the async fetch below
    // doesn't re-enter this handler.
    convoyProvider.consumeJourneyEndedEvent();
    final journeyId = event.journeyId;

    setState(() => _isJourneyExitInProgress = true);

    _navigationProvider?.stopNavigation();

    // Fetch the completed journey so we can pass full details to the
    // details screen. Falls back to home if the fetch fails.
    () async {
      final journeyProvider = context.read<JourneyProvider>();
      await journeyProvider.fetchJourneyById(journeyId);
      if (!mounted) return;

      final journey = journeyProvider.currentJourney;
      if (journey != null && journey.id == journeyId) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                JourneyDetailsScreen(journey: journey, showDoneButton: true),
          ),
          (route) => false,
        );
      } else {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }();
  }

  /// Show confirmation dialog for ending journey
  void _showEndJourneyConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'End Journey?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to end this convoy journey? This will stop coordination for all members.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endJourney();
            },
            child: const Text(
              'End Journey',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaveJourneyConfirmation() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Leave Journey?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You will stop sharing your location and leave this convoy. The journey will continue for everyone else.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Stay', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _leaveJourney();
            },
            child: const Text(
              'Leave Journey',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Show convoy metrics bottom sheet
  void _showConvoyMetricsBottomSheet() {
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.id;
    final currentJourney = journeyProvider.currentJourney;

    // For metrics, use full snapshot to include all members for distance calculations
    final snapshot = convoyProvider.getFullSnapshot();

    if (snapshot != null && currentJourney != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ConvoyMetricsBottomSheet(
          snapshot: snapshot,
          journeyName: currentJourney.name,
          onEndJourney: () {
            Navigator.pop(context);
            // TODO: Implement journey end functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('End journey functionality coming soon!'),
              ),
            );
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_statusNotifier.clear());
    WidgetsBinding.instance.removeObserver(this);
    _mapboxMap = null;
    // Stop the peer-marker interpolation ticker before the map handle is gone.
    _stopInterpolationTicker();
    _navigationFrameTicker?.cancel();
    _navigationFrameTicker = null;
    // Stop the camera-follow GPS stream — independent of convoy coordination
    _cameraFollowSubscription?.cancel();
    _cameraFollowSubscription = null;
    // Detach the polyline-trim listener before releasing the provider reference.
    _navigationProvider?.removeListener(_onNavigationProgress);
    // Stop the navigation layer — independent of convoy coordination.
    // Uses the cached reference because context.read<>() is unsafe here.
    _navigationProvider?.stopNavigation();
    // Best-effort puck cleanup — we're losing the map handle anyway.
    unawaited(_drawSnappedPuck(null).catchError((Object _) {}));
    // Don't stop convoy coordination when leaving map screen
    // The journey should continue in the background
    // Only stop convoy coordination when journey is actually ended
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to journey and convoy changes to update markers and react to
    // server-driven events (journey-ended triggers _handleJourneyEndedEvent).
    final currentJourney = context.watch<JourneyProvider>().currentJourney;
    final convoySnapshot = context.watch<ConvoyProvider>().snapshot;
    final convoyConnectionState = context
        .watch<ConvoyProvider>()
        .connectionState;
    final convoyError = context.watch<ConvoyProvider>().errorMessage;
    // Watching these triggers rebuilds when server events arrive so the
    // post-frame callbacks can react immediately.
    context.watch<ConvoyProvider>().lastJourneyEndedEvent;
    context.watch<ConvoyProvider>().lastArrivalEvent;
    final currentUserId = context.watch<AuthProvider>().user?.id ?? '';
    final isLeader =
        currentJourney != null &&
        currentUserId.isNotEmpty &&
        currentJourney.leaderId == currentUserId;

    // Marker updates are driven by didChangeDependencies(), not build().

    // Post-frame: check convoy start + handle server-driven events.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAndStartConvoyCoordination();
      _handleArrivalEvent();
      _handleJourneyEndedEvent();
    });

    return Scaffold(
      body: Stack(
        children: [
          // Standard Mapbox Map.
          // onScrollListener fires only on user-initiated panning — not on
          // programmatic setCamera / flyTo calls — so no _isProgrammaticCameraMove
          // guard is needed here. The old GestureDetector(onPanStart) wrapper was
          // winning the Flutter gesture arena and blocking the native MapWidget
          // from receiving touch events, making the map impossible to pan.
          RepaintBoundary(
            child: MapWidget(
              key: ValueKey('mapbox_map_$_mapGeneration'),
              onMapCreated: _onMapCreated,
              onScrollListener: (_) {
                if (!_isProgrammaticCameraMove) {
                  _cameraFollowEnabled = false;
                }
              },
              styleUri: MapboxStyles.DARK,
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: Position(36.8219, -1.2921), // Nairobi
                ),
                zoom: 10,
              ),
            ),
          ),

          // Convoy Status Bar - Show when active journey exists
          if (currentJourney != null &&
              currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: _showConvoyBottomSheet,
                onLongPress: _showConvoyManagementOptions,
                child: ConvoyStatusBar(
                  snapshot: convoySnapshot,
                  connectionState: convoyConnectionState,
                  onTap: _showConvoyBottomSheet,
                  onBack: () => Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/home', (route) => false),
                ),
              ),
            ),

          // Turn-by-turn instruction card — hidden once user has arrived
          if (currentJourney != null &&
              currentJourney.status == JourneyStatus.ACTIVE &&
              !_currentUserHasArrived)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 0,
              right: 0,
              child: Consumer<NavigationProvider>(
                builder: (context, nav, _) {
                  return TurnInstructionCard(
                    progress: nav.currentProgress,
                    isVoiceEnabled: nav.isVoiceEnabled,
                    onToggleVoice: () =>
                        nav.setVoiceEnabled(!nav.isVoiceEnabled),
                  );
                },
              ),
            ),

          // Arrival confirmation banner — replaces the turn card once the
          // current user is confirmed at the destination. Stays visible until
          // all members arrive and the journey-ended event navigates away.
          if (currentJourney != null &&
              currentJourney.status == JourneyStatus.ACTIVE &&
              _currentUserHasArrived)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 16,
              right: 16,
              child: Consumer<ConvoyProvider>(
                builder: (context, convoy, _) {
                  final arrived = convoy.arrivedCount;
                  final total = convoy.totalMemberCount;
                  final allArrived = total > 0 && arrived >= total;
                  final waiting = total > arrived ? total - arrived : 0;
                  return _ArrivalBanner(
                    arrived: arrived,
                    total: total,
                    allArrived: allArrived,
                    waiting: waiting,
                    isLeader: isLeader,
                    onEndJourney: isLeader ? _showEndJourneyConfirmation : null,
                  );
                },
              ),
            ),

          // Route loading indicator — visible only while POST /maps/route is in flight
          if (currentJourney != null &&
              currentJourney.status == JourneyStatus.ACTIVE)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 0,
              right: 0,
              child: Consumer<MapProvider>(
                builder: (context, mapProvider, _) {
                  if (!mapProvider.isFetchingRoute)
                    return const SizedBox.shrink();
                  return const _RouteLoadingPill();
                },
              ),
            ),

          // Map Header - Top Overlay (when no active journey)
          if (currentJourney == null ||
              currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.topCenter,
              child: MapHeaderOverlay(),
            ),

          // Journey Progress Card - Bottom Overlay (collapsed pill by default)
          if (currentJourney != null &&
              currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.bottomCenter,
              child: Consumer<NavigationProvider>(
                builder: (context, navigation, _) => JourneyProgressCard(
                  journey: currentJourney,
                  convoySnapshot: convoySnapshot,
                  currentUserId: currentUserId,
                  isLeader: isLeader,
                  routeProgress: navigation.currentProgress,
                  onEndJourney: _showEndJourneyConfirmation,
                  onLeaveJourney: _showLeaveJourneyConfirmation,
                  isActionInProgress: _isJourneyExitInProgress,
                  isExpanded: _isProgressCardExpanded,
                  onToggleExpanded: () => setState(
                    () => _isProgressCardExpanded = !_isProgressCardExpanded,
                  ),
                ),
              ),
            ),

          // Map Bottom Bar - Show when no active journey
          if (currentJourney == null ||
              currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.bottomCenter,
              child: MapJourneyOverlay(),
            ),

          // Recenter button — active journey.
          // Shifts up by the card-expansion delta (182 px) so it always clears
          // the expanded card header.
          if (currentJourney != null &&
              currentJourney.status == JourneyStatus.ACTIVE)
            Positioned(
              bottom: _isProgressCardExpanded ? 254 : 72,
              right: 16,
              child: GestureDetector(
                onTap: _recenterOnUser,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),

          // Recenter button — no active journey: sits above the bottom overlay
          if (currentJourney == null ||
              currentJourney.status != JourneyStatus.ACTIVE)
            Positioned(
              bottom: 120,
              right: 16,
              child: GestureDetector(
                onTap: _recenterOnUser,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),

          // Error Banner - Show when convoy has errors
          if (convoyError != null && convoyError.isNotEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 120, left: 16, right: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        convoyError,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _showConvoyManagementOptions,
                      icon: const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Convoy Management',
                    ),
                  ],
                ),
              ),
            ),

          if (_isJourneyExitInProgress)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: AbsorbPointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFE8002D)),
                          SizedBox(height: 14),
                          Text(
                            'Finishing journey…',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      // Convoy Metrics FAB - Show when active convoy exists
      // floatingActionButton: (currentJourney != null &&
      //     currentJourney.status == JourneyStatus.ACTIVE &&
      //     convoySnapshot != null &&
      //     convoySnapshot.members.isNotEmpty)
      //   ? FloatingActionButton(
      //       onPressed: _showConvoyMetricsBottomSheet,
      //       backgroundColor: const Color(0xFFE53E3E),
      //       child: const Icon(
      //         Icons.analytics_outlined,
      //         color: Colors.white,
      //       ),
      //     )
      //   : null,
      // floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

/// Arrival confirmation card shown to the current user once the backend
/// confirms they've reached the destination. Replaces the turn-instruction
/// card in the top slot and stays visible until everyone arrives and the
/// backend fires `journey-ended` (which auto-navigates away).
class _ArrivalBanner extends StatelessWidget {
  const _ArrivalBanner({
    required this.arrived,
    required this.total,
    required this.allArrived,
    required this.waiting,
    required this.isLeader,
    this.onEndJourney,
  });

  final int arrived;
  final int total;
  final bool allArrived;
  final int waiting;
  final bool isLeader;
  final VoidCallback? onEndJourney;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allArrived
              ? Colors.green.withOpacity(0.6)
              : Colors.green.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flag, color: Colors.green, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    allArrived ? 'Everyone has arrived!' : "You've arrived!",
                    style: GoogleFonts.rajdhani(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (!allArrived)
                    Text(
                      total > 1
                          ? 'Waiting for $waiting more member${waiting == 1 ? '' : 's'} — $arrived/$total arrived'
                          : 'Journey complete',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colors.silver,
                        height: 1.3,
                      ),
                    )
                  else
                    Text(
                      'Ending journey…',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colors.silver,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
            if (isLeader && !allArrived && onEndJourney != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onEndJourney,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.electricRed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'End',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteLoadingPill extends StatelessWidget {
  const _RouteLoadingPill();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.carbonBlack.withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.electricRed.withOpacity(0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation(colors.electricRed),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Calculating route',
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
