import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/services/car_toast_service.dart';
import '../../../core/services/journey_location_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/tulink_colors.dart';
import '../../../core/utils/logger.dart';
import '../data/models/route_result_model.dart';
import 'providers/map_provider.dart';
import 'services/convoy_interpolation_service.dart';
import '../../journeys/presentation/providers/journey_provider.dart';
import '../../journeys/data/models/journey_model.dart';
import '../../journeys/domain/entities/journey.dart';
import '../../convoy/presentation/providers/convoy_provider.dart';
import '../../convoy/presentation/widgets/convoy_status_bar.dart';
import '../../convoy/presentation/widgets/convoy_bottom_sheet.dart';
import '../../convoy/presentation/widgets/convoy_metrics_bottom_sheet.dart';
import '../../convoy/presentation/widgets/journey_progress_card.dart';
import '../../convoy/presentation/widgets/convoy_route_line.dart';
import '../../convoy/presentation/services/journey_status_notifier.dart';
import '../../convoy/presentation/utils/convoy_member_presentation.dart';
import '../../convoy/domain/entities/convoy_snapshot.dart';
import '../../convoy/domain/entities/journey_ended_event.dart';
import '../../convoy/domain/entities/member_position.dart';
import '../../convoy/domain/entities/route_updated_event.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../home/presentation/state/journey_ended_event_scope.dart';
import 'widgets/turn_instruction_card.dart';
import 'providers/navigation_provider.dart';
import '../domain/entities/route_progress.dart';
import 'utils/route_rendering.dart';
import 'controllers/persistent_map_controller.dart';

/// The live convoy layer, drawn over the application's single persistent map.
///
/// This owns everything that only makes sense while a journey is running:
/// convoy member markers, the route-snapped puck, turn-by-turn progress,
/// camera-follow, arrival handling and journey exit. It deliberately does **not**
/// own a `MapWidget` — it draws through [PersistentMapController], so starting
/// and ending a journey no longer swaps one map for another.
///
/// Mount it only while a journey is running; the host shell decides that from
/// [MapExperienceState].
class LiveJourneyExperience extends StatefulWidget {
  const LiveJourneyExperience({
    super.key,
    required this.controller,
    this.onExit,
    this.onCompleted,
    this.onBack,
    this.onEndingChanged,
    this.onEndedWithoutSummary,
  });

  /// Handle to the one map surface in the app.
  final PersistentMapController controller;

  /// Invoked when the journey is over and the layer should be torn down. The
  /// host returns to its non-journey state rather than popping a route — there
  /// is no map screen to pop back from any more.
  final VoidCallback? onExit;

  /// Invoked when the journey completed and there is a summary to show. The
  /// host renders it over the same map, so the route the user just drove stays
  /// on screen behind the summary.
  final ValueChanged<Journey>? onCompleted;

  /// Invoked with the id of a journey that has ended but whose summary could
  /// not be loaded, so the host can release it from selection.
  final ValueChanged<String>? onEndedWithoutSummary;

  /// Back pressed. This must never end or abandon the journey — the host
  /// decides what Back means (it collapses this chrome), and the journey keeps
  /// running underneath.
  final VoidCallback? onBack;

  /// Reports whether a journey teardown is in flight, so the host can drive the
  /// authoritative `ending` experience state and keep chrome consistent.
  final ValueChanged<bool>? onEndingChanged;

  @override
  State<LiveJourneyExperience> createState() => _LiveJourneyExperienceState();
}

class _LiveJourneyExperienceState extends State<LiveJourneyExperience>
    with WidgetsBindingObserver {
  PointAnnotationManager? _pointAnnotationManager;
  String? _activeJourneyId;
  ConvoySnapshot? _lastSnapshot;
  int _lastUpdateHash = 0;
  bool _disposed = false;
  bool _isAppActive = true;

  int _rosterMemberCount(Journey journey) => <String>{
    journey.leaderId,
    for (final participant in journey.participants ?? const <Participant>[])
      if (!const {
        'INVITED',
        'LEFT',
        'DECLINED',
      }.contains(participant.status.toUpperCase()))
        participant.userId,
  }.length;

  /// The map surface is owned by the host shell, not by this layer.
  MapboxMap? get _mapboxMap => widget.controller.map;

  /// Bumped by the host whenever the native surface is rebuilt.
  int get _mapGeneration => widget.controller.generation;

  /// Generation this layer has already attached to, so a rebuild is detected
  /// exactly once.
  int? _attachedGeneration;

  /// [PersistentMapController.userPanTick] value last observed, used to notice
  /// a hand pan without the layer having to own the gesture listener.
  int _lastUserPanTick = 0;
  int _lastRouteUpdatedTick = 0;

  /// Bounded location access shared with [ConvoyProvider]; see [LocationService].
  final LocationService _locationService = ServiceLocator().locationService;

  /// Shared continuous journey stream. Map camera-follow never opens another
  /// native GPS session of its own.
  final JourneyLocationService _journeyLocationService =
      ServiceLocator().journeyLocationService;

  /// Pending "draw the route once we finally get a fix" listener, armed only
  /// when there is neither a cached route nor an origin. See
  /// [_scheduleRouteRetryOnNextFix].
  StreamSubscription<geo.Position>? _routeRetrySubscription;
  String? _routeRetryJourneyId;

  /// Guards against concurrent convoy reconnect attempts.
  bool _isReconnectingConvoy = false;

  /// True when it's safe to call the Mapbox channel — set false on dispose
  /// so async chains that resume after the widget is unmounted bail out
  /// instead of throwing PlatformException on a dead channel.
  bool get _canUseMap =>
      !_disposed && _isAppActive && mounted && _mapboxMap != null;

  /// Coalesces duplicate route setup calls from map creation and convoy
  /// startup. Both lifecycle paths run during the same navigation transition.
  Future<void>? _routeSetupFuture;
  String? _routeSetupJourneyId;
  Timer? _canonicalRouteRetryTimer;
  String? _canonicalRouteRetryJourneyId;
  int _canonicalRouteRetryAttempt = 0;
  static const int _maxCanonicalRouteRetryAttempts = 5;

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
  /// `null` = unknown (nothing applied yet).
  bool? _puckEnabled;
  bool _legacyCustomPucksCleared = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastUserPanTick = widget.controller.userPanTick;
    widget.controller.addListener(_onMapControllerChanged);
    // The surface is frequently already attached — the host map outlives this
    // layer, so there is no "map created" event to wait for.
    _onMapControllerChanged();
  }

  @override
  void didUpdateWidget(covariant LiveJourneyExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onMapControllerChanged);
    _attachedGeneration = null;
    _lastUserPanTick = widget.controller.userPanTick;
    widget.controller.addListener(_onMapControllerChanged);
    _onMapControllerChanged();
  }

  /// Reacts to the two things the host can do to the shared surface: replace it
  /// (new generation) and report a user pan.
  void _onMapControllerChanged() {
    if (_disposed || !mounted) return;

    if (widget.controller.userPanTick != _lastUserPanTick) {
      _lastUserPanTick = widget.controller.userPanTick;
      // An explicit pan yields camera control until the user taps recenter.
      // The guard keeps a camera animation we started from being mistaken for
      // the user grabbing the map.
      if (!_isProgrammaticCameraMove) {
        _cameraFollowEnabled = false;
      }
    }

    final map = widget.controller.map;
    if (map == null || _attachedGeneration == _mapGeneration) return;
    _attachedGeneration = _mapGeneration;
    // Surface-local handles belong to the old surface; drop them before redraw.
    _pointAnnotationManager = null;
    _lastUpdateHash = 0;
    _puckEnabled = null;
    _legacyCustomPucksCleared = false;
    _lastTrimAt = null;
    unawaited(
      _attachToMap(map).catchError((Object e) {
        print('❌ Failed to attach live journey layer to map: $e');
      }),
    );
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

    _isAppActive = true;

    // Surface recreation is the *host's* responsibility and the host observes
    // the same lifecycle event. Recreating here too produced two generation
    // bumps and two restore passes for a single resume, so this layer only
    // reacts: [_onMapControllerChanged] restores route, destination and markers
    // when the host's rebuild lands.
  }

  /// Restore the whole journey layer onto a (possibly brand new) surface.
  ///
  /// Idempotent, and safe to run repeatedly: every draw below either replaces
  /// its own style layer or is keyed by journey, so a redundant attach costs
  /// work but cannot duplicate geometry.
  Future<void> _attachToMap(MapboxMap mapboxMap) async {
    // Guards against a map recreated mid-restore (background/foreground churn):
    // work started for an older surface must not draw onto the new one.
    final generation = _mapGeneration;
    await mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _pointAnnotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();
    if (!mounted || generation != _mapGeneration) return;

    // User location is drawn independently and is NOT awaited here: the puck is
    // cosmetic, whereas the journey draw below is the reason the screen exists.
    // Awaiting a location fix before drawing the journey is what used to leave
    // the live screen empty on devices without GPS.
    unawaited(
      _enableUserLocation(mapboxMap).catchError((Object e) {
        print('❌ Failed to enable user location: $e');
      }),
    );

    // Draw static journey data immediately — does not wait for any WebSocket
    // snapshot to arrive. The destination is journey data, not convoy data.
    if (mounted && generation == _mapGeneration) {
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

          final pos = await _locationService.getCurrentPosition();
          if (pos == null)
            return; // GPS not ready — leave the overview in place

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
    _syncActiveJourneyLayer();
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
  /// Retry route initialization once the device produces a position.
  ///
  /// Reached when there was no cached route *and* no origin. Listens for the
  /// first fix, then rebuilds the route for [journey]. Guarded by journey id so
  /// a fix arriving after a switch cannot draw the previous journey's route.
  void _scheduleRouteRetryOnNextFix(Journey journey) {
    if (_routeRetryJourneyId == journey.id && _routeRetrySubscription != null) {
      return; // already waiting for this journey
    }
    _cancelRouteLocationRetry();
    _routeRetryJourneyId = journey.id;
    void retry(geo.Position position) {
      if (!mounted || _routeRetryJourneyId != journey.id) return;
      _cancelRouteLocationRetry();
      unawaited(
        _drawActualRoute(
          journey,
          knownLat: position.latitude,
          knownLng: position.longitude,
        ),
      );
    }

    _routeRetrySubscription = _journeyLocationService.positions.listen(
      retry,
      onError: (Object e) => print('⚠️ Route retry stream error: $e'),
    );
    final latest = _journeyLocationService.latestPosition;
    if (latest != null) retry(latest);
  }

  void _cancelRouteLocationRetry() {
    _routeRetrySubscription?.cancel();
    _routeRetrySubscription = null;
    _routeRetryJourneyId = null;
  }

  /// Frame the destination alone. Used whenever the user's position is
  /// unavailable, so the map still shows something meaningful rather than
  /// sitting on a default regional camera.
  Future<void> _centerOnDestination(Journey journey) async {
    if (!mounted || _mapboxMap == null) return;
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
    } catch (e) {
      print('⚠️ Could not center on destination: $e');
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  Future<void> _fitCameraToJourney(Journey journey) async {
    if (_mapboxMap == null) return;

    // Bounded: without a fix this returns null rather than hanging, so the
    // camera still frames the destination instead of never moving at all.
    final pos = await _locationService.getCurrentPosition();
    if (!mounted || _mapboxMap == null) return;

    if (pos == null) {
      await _centerOnDestination(journey);
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
    if (_mapboxMap == null || !mounted) return;

    final mapProvider = context.read<MapProvider>();
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) {
      print('⚠️ Cannot load route without an authenticated user scope');
      return;
    }

    // The surface this draw belongs to. Every route decision below is stamped
    // with it, so work that resolved against a surface which has since been
    // rebuilt cannot paint the new one.
    final generation = _mapGeneration;

    RouteResultModel? route = await mapProvider.fetchCanonicalRoute(
      userId: userId,
      journeyId: journey.id,
      destLat: journey.destination.latitude,
      destLng: journey.destination.longitude,
      surfaceGeneration: generation,
    );
    if (!mounted || _mapboxMap == null || generation != _mapGeneration) return;

    // Every member reads the same committed route. Only the leader may create
    // the first version when none exists; followers wait for the server event
    // instead of calculating a divergent polyline on their own device.
    if (route == null) {
      final currentUserId = context.read<AuthProvider>().user?.id;
      if (currentUserId != journey.leaderId) {
        await _centerOnDestination(journey);
        _scheduleCanonicalRouteRetry(journey);
        return;
      }

      final latest = _journeyLocationService.latestPosition;
      final originLat = knownLat ?? latest?.latitude;
      final originLng = knownLng ?? latest?.longitude;
      if (originLat == null || originLng == null) {
        await _centerOnDestination(journey);
        _scheduleRouteRetryOnNextFix(journey);
        return;
      }
      route = await mapProvider.replaceCanonicalRoute(
        userId: userId,
        journeyId: journey.id,
        originLat: originLat,
        originLng: originLng,
        destLat: journey.destination.latitude,
        destLng: journey.destination.longitude,
        baseVersion: 0,
        reason: 'INITIAL',
        surfaceGeneration: generation,
      );
    }

    if (route == null || !mounted || _mapboxMap == null) return;
    _cancelCanonicalRouteRetry();
    // The surface was rebuilt while the route was being resolved: these layer
    // ids belong to a style that no longer exists, and whichever layer owns the
    // new surface redraws its own geometry.
    if (generation != _mapGeneration) return;

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
        journeyId: journey.id,
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
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || journey.leaderId != userId) return;
    print('🧭 Handling reroute for journey ${journey.id}');

    // Grab the current position from the live navigation stream before clearing
    // state. When off-route, snappedLatitude/Longitude holds the raw GPS
    // coordinate (MapMatchingService returns raw when deviation > threshold),
    // so it is the correct origin for the new route — and it's already in hand,
    // avoiding a second GPS cold-start wait.
    final progress = context.read<NavigationProvider>().currentProgress;
    final knownLat = progress?.snappedLatitude;
    final knownLng = progress?.snappedLongitude;

    final latest = _journeyLocationService.latestPosition;
    final originLat = knownLat ?? latest?.latitude;
    final originLng = knownLng ?? latest?.longitude;
    if (originLat == null || originLng == null) return;

    final mapProvider = context.read<MapProvider>();
    var baseVersion = mapProvider.canonicalVersionFor(
      userId: userId,
      journeyId: journey.id,
      destLat: journey.destination.latitude,
      destLng: journey.destination.longitude,
    );
    if (baseVersion == null) {
      await mapProvider.fetchCanonicalRoute(
        userId: userId,
        journeyId: journey.id,
        destLat: journey.destination.latitude,
        destLng: journey.destination.longitude,
        surfaceGeneration: _mapGeneration,
      );
      baseVersion = mapProvider.canonicalVersionFor(
        userId: userId,
        journeyId: journey.id,
        destLat: journey.destination.latitude,
        destLng: journey.destination.longitude,
      );
    }
    if (baseVersion == null) return;

    final newRoute = await mapProvider.replaceCanonicalRoute(
      userId: userId,
      journeyId: journey.id,
      originLat: originLat,
      originLng: originLng,
      destLat: journey.destination.latitude,
      destLng: journey.destination.longitude,
      baseVersion: baseVersion,
      reason: 'LEADER_REROUTE',
      surfaceGeneration: _mapGeneration,
    );
    if (newRoute == null || !mounted) return;

    // Reset throttle state so trim and puck start immediately on the new route.
    _lastTrimAt = null;

    await _drawActualRoute(journey, knownLat: originLat, knownLng: originLng);
    AppLogger.info(
      'Reroute fetched for ${journey.id}: '
      '${newRoute.coordinates.length} coordinates',
    );
    if (mounted) {
      context.read<NavigationProvider>().loadRoute(newRoute);
    }
  }

  void _scheduleCanonicalRouteRetry(Journey journey) {
    if (_canonicalRouteRetryJourneyId != journey.id) {
      _canonicalRouteRetryTimer?.cancel();
      _canonicalRouteRetryJourneyId = journey.id;
      _canonicalRouteRetryAttempt = 0;
    }
    if (_canonicalRouteRetryAttempt >= _maxCanonicalRouteRetryAttempts) return;

    _canonicalRouteRetryTimer?.cancel();
    _canonicalRouteRetryAttempt++;
    _canonicalRouteRetryTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final current = context.read<JourneyProvider>().currentJourney;
      if (current?.id != journey.id ||
          current?.status != JourneyStatus.ACTIVE) {
        _cancelCanonicalRouteRetry();
        return;
      }
      unawaited(_drawActualRoute(journey));
    });
  }

  void _cancelCanonicalRouteRetry() {
    _canonicalRouteRetryTimer?.cancel();
    _canonicalRouteRetryTimer = null;
    _canonicalRouteRetryJourneyId = null;
    _canonicalRouteRetryAttempt = 0;
  }

  /// True if a route's last coordinate is within ~110 m of the given target.
  /// Used to detect whether a cached route was generated for the current
  /// journey's destination. [coord] is [lng, lat].
  /// Snap the camera to the user's current GPS position and re-enable follow
  /// Animates the camera back to the device's current position and
  /// re-enables follow mode. Called by the recenter button after the user
  /// has panned away.
  Future<void> _recenterOnUser() async {
    if (_mapboxMap == null) return;
    final pos = await _locationService.getCurrentPosition();
    if (pos == null || !mounted || _mapboxMap == null) return;

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

    // Prefer snapped position when navigation is active. Falls back to raw
    // GPS when navigation is inactive or no progress snapshot exists yet.
    final progress = _navigationProvider?.currentProgress;
    if (progress == null) {
      unawaited(_drawRawPuck(position));
    }
    final centerLat =
        _displayedNavigationLatitude ??
        progress?.snappedLatitude ??
        position.latitude;
    final centerLng =
        _displayedNavigationLongitude ??
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
    final convoy = context.watch<ConvoyProvider>();
    if (convoy.routeUpdatedTick != _lastRouteUpdatedTick) {
      _lastRouteUpdatedTick = convoy.routeUpdatedTick;
      final event = convoy.lastRouteUpdatedEvent;
      if (event != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_applyCanonicalRouteUpdate(event));
        });
      }
    }
    // Refresh markers only when provider dependencies actually change,
    // rather than on every build().
    if (_mapboxMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateMarkers();
      });
    }
  }

  Future<void> _applyCanonicalRouteUpdate(RouteUpdatedEvent event) async {
    final pending = _routeSetupFuture;
    if (pending != null) await pending;
    if (!mounted) return;
    final journey = context.read<JourneyProvider>().currentJourney;
    final userId = context.read<AuthProvider>().user?.id;
    if (journey == null ||
        userId == null ||
        journey.id != event.journeyId ||
        journey.status != JourneyStatus.ACTIVE) {
      return;
    }
    final heldVersion = context.read<MapProvider>().canonicalVersionFor(
      userId: userId,
      journeyId: journey.id,
      destLat: journey.destination.latitude,
      destLng: journey.destination.longitude,
    );
    if ((heldVersion ?? 0) >= event.routeVersion) return;
    await _drawActualRoute(journey);
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
            longitude: startLng + (target.snappedLongitude - startLng) * easedT,
            latitude: startLat + (target.snappedLatitude - startLat) * easedT,
            segmentIndex: target.currentSegmentIndex,
          )
        : interpolateRoutePosition(
            routeCoordinates: route.coordinates,
            startLongitude: startLng,
            startLatitude: startLat,
            startSegmentIndex:
                _displayedNavigationSegmentIndex ?? target.currentSegmentIndex,
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

  /// Keep the native directional location puck active during navigation.
  Future<void> _drawSnappedPuck(RouteProgress? _) async {
    if (!_canUseMap) return;
    await _useDirectionalLocationPuck();
  }

  /// Use the same native puck while acquiring a route and while navigating.
  Future<void> _drawRawPuck(geo.Position _) async {
    if (!_canUseMap) return;
    await _useDirectionalLocationPuck();
  }

  Future<void> _useDirectionalLocationPuck() async {
    if (!_canUseMap) return;
    if (!_legacyCustomPucksCleared) {
      for (final layer in const [
        'snapped-puck-dot',
        'snapped-puck-ring',
        'raw-puck-dot',
        'raw-puck-ring',
      ]) {
        try {
          await _mapboxMap!.style.removeStyleLayer(layer);
        } catch (_) {}
      }
      for (final source in const ['snapped-puck-source', 'raw-puck-source']) {
        try {
          await _mapboxMap!.style.removeStyleSource(source);
        } catch (_) {}
      }
      _legacyCustomPucksCleared = true;
    }
    await _setBuiltInPuckEnabled(true);
  }

  /// Set Mapbox's built-in location puck on/off, tracking the applied state so
  /// we never spam the platform channel. Errors are logged, not swallowed.
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
          // Course follows direction of travel and is more useful in a
          // driving journey than the phone's physical compass orientation.
          puckBearing: PuckBearing.COURSE,
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

      await _setBuiltInPuckEnabled(true);
      // Bounded: a device with no fix yields null instead of an unresolved
      // future. This used to be an unbounded getCurrentPosition() awaited by
      // _onMapCreated, which meant no fix == no destination pin, no route and
      // no camera fit, forever.
      final position = await _locationService.getCurrentPosition();
      if (!mounted || position == null) return;
      await _drawRawPuck(position);
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
          rosterMemberCount: _rosterMemberCount(journey),
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

  /// Re-establish the convoy connection for the journey already in progress.
  ///
  /// Distinct from [_retryLocation]: this recovers the socket/room, not the GPS
  /// fix. It never recreates the journey — the same journey id is re-joined.
  Future<void> _reconnectConvoy(String journeyId) async {
    if (_isReconnectingConvoy) return; // no concurrent attempts
    // The attempt id itself is owned by ConvoyProvider, which outlives this
    // widget; this flag only drives local progress affordances.
    setState(() => _isReconnectingConvoy = true);
    try {
      final convoy = context.read<ConvoyProvider>();
      await convoy.reconnect(journeyId);
      if (!mounted) return;
      if (convoy.snapshot == null && convoy.errorMessage != null) {
        context.showWarningToast(convoy.errorMessage!);
      }
    } finally {
      if (mounted) setState(() => _isReconnectingConvoy = false);
    }
  }

  /// Retry location acquisition without tearing down the convoy room.
  Future<void> _retryLocation() async {
    final convoy = context.read<ConvoyProvider>();
    final recovered = await convoy.retryLocationPublishing();
    if (!mounted) return;
    if (!recovered) {
      context.showWarningToast(
        convoy.locationFailure?.message ?? 'Still waiting for your location',
      );
    }
  }

  /// Keeps map-only journey state aligned with the app-owned live session.
  void _syncActiveJourneyLayer() {
    if (!mounted) return;
    final journeyProvider = context.read<JourneyProvider>();
    final currentJourney = journeyProvider.currentJourney;

    if (currentJourney != null &&
        currentJourney.status == JourneyStatus.ACTIVE) {
      final isNewJourney = _activeJourneyId != currentJourney.id;
      if (isNewJourney) _cancelCanonicalRouteRetry();
      _activeJourneyId = currentJourney.id;

      // Note: do NOT disable the built-in puck here. It stays on until the
      // snapped puck actually starts drawing (see _drawSnappedPuck), otherwise
      // the user has no puck during the journey overview / pre-driving window.

      // Ensure the destination pin and route are drawn from static journey
      // data even when the map screen is reached without _onMapCreated firing.
      if (isNewJourney && _mapboxMap != null) {
        _drawDestinationPin(currentJourney);
        _drawActualRoute(currentJourney);
      }

      // Presentation subscribes to the app-owned journey stream. Disposing this
      // widget detaches camera follow without stopping screen-off publishing.
      if (_cameraFollowSubscription == null) {
        _cameraFollowSubscription = _journeyLocationService.positions.listen(
          _updateCameraFollow,
        );
        final latest = _journeyLocationService.latestPosition;
        if (latest != null) unawaited(_updateCameraFollow(latest));
      }
      return;
    }

    _activeJourneyId = null;
    _cancelCanonicalRouteRetry();
    unawaited(_cameraFollowSubscription?.cancel());
    _cameraFollowSubscription = null;
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
                  unawaited(_reconnectConvoy(currentJourney.id));
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
  /// Track teardown locally *and* publish it, so the host's authoritative
  /// experience state can reach `ending` instead of it being unreachable.
  void _setExitInProgress(bool value) {
    if (!mounted || _isJourneyExitInProgress == value) return;
    setState(() => _isJourneyExitInProgress = value);
    widget.onEndingChanged?.call(value);
  }

  Future<void> _endJourney() async {
    if (_isJourneyExitInProgress) return;
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();

    // Capture before any await — providers may clear this during the async gap.
    final journeyId = journeyProvider.currentJourney?.id ?? _activeJourneyId;

    if (journeyId == null) {
      // Journey already cleared externally — hand the shell back its map.
      widget.onExit?.call();
      return;
    }

    _setExitInProgress(true);
    final success = await journeyProvider.endJourney(journeyId);

    if (!mounted) return;

    if (success) {
      await _navigationProvider?.stopNavigation();
      await convoyProvider.stopCoordination();
      if (!mounted) return;
      final completedJourney = journeyProvider.lastCompletedJourney;
      journeyProvider.consumeLastCompletedJourney();

      // The summary is rendered by the shell over the same map, so the route
      // just driven stays visible behind it instead of being replaced by a
      // separate screen.
      if (completedJourney != null) {
        widget.onCompleted?.call(completedJourney);
      } else {
        widget.onExit?.call();
      }
    } else {
      _setExitInProgress(false);
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

    _setExitInProgress(true);
    final success = await journeyProvider.leaveJourney(journeyId);
    if (!mounted) return;

    if (!success) {
      _setExitInProgress(false);
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
    widget.onExit?.call();
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
  /// Build the finished journey from the `journey-ended` payload.
  ///
  /// Returns null when the payload is absent or unparseable, so the caller can
  /// fall back rather than crash on an unexpected shape.
  Journey? _journeyFromEndedEvent(JourneyEndedEvent event) {
    final raw = event.journey;
    if (raw == null || raw.isEmpty) return null;
    try {
      // JourneyModel extends Journey, so it is already the entity.
      return JourneyModel.fromJson(raw);
    } catch (e) {
      print('⚠️ Could not parse journey from journey-ended payload: $e');
      return null;
    }
  }

  /// A disconnected client may learn that the journey ended from a typed
  /// publish rejection rather than the socket broadcast. That response has no
  /// finished-journey payload, but it is authoritative. Preserve the selected
  /// journey's summary fields and mark that same identity completed instead of
  /// discarding the summary or treating a generic network error as terminal.
  Journey? _completedSelectedJourney(JourneyEndedEvent event) {
    if (event.reason != 'terminal-reconciliation') return null;
    final selected = context.read<JourneyProvider>().currentJourney;
    if (selected == null || selected.id != event.journeyId) return null;
    return Journey(
      id: selected.id,
      inviteCode: selected.inviteCode,
      name: selected.name,
      leaderId: selected.leaderId,
      status: JourneyStatus.COMPLETED,
      destination: selected.destination,
      destinationName: selected.destinationName,
      destinationAddress: selected.destinationAddress,
      lagThresholdMeters: selected.lagThresholdMeters,
      createdAt: selected.createdAt,
      updatedAt: selected.updatedAt,
      startTime: selected.startTime,
      participants: selected.participants,
      startedAt: selected.startedAt,
      completedAt: event.endedAt ?? DateTime.now(),
      scheduledFor: selected.scheduledFor,
      autoStart: selected.autoStart,
    );
  }

  void _handleJourneyEndedEvent() {
    if (!mounted || _isJourneyExitInProgress) return;
    final convoyProvider = context.read<ConvoyProvider>();
    final event = convoyProvider.lastJourneyEndedEvent;
    if (event == null) return;

    final selectedJourneyId = context
        .read<JourneyProvider>()
        .currentJourney
        ?.id;
    if (!isJourneyEndedEventCurrent(
      eventJourneyId: event.journeyId,
      selectedJourneyId: selectedJourneyId,
      activeLayerJourneyId: _activeJourneyId,
    )) {
      // The event belongs to a journey that previously owned this provider.
      // Drop it so it cannot keep re-triggering, but never let it tear down the
      // journey currently selected by the host.
      convoyProvider.consumeJourneyEndedEvent();
      return;
    }

    // Consume up-front so a rebuild triggered by the async fetch below
    // doesn't re-enter this handler.
    convoyProvider.consumeJourneyEndedEvent();
    final journeyId = event.journeyId;

    _setExitInProgress(true);

    _navigationProvider?.stopNavigation();

    // Prefer the journey carried on the event itself. Completing a journey
    // marks every participant LEFT, so `GET /journeys/{id}` answers 403 to the
    // very people who were on it — re-fetching here could never succeed after a
    // server-driven end, which is why the completion summary never appeared.
    final fromEvent = _journeyFromEndedEvent(event);
    if (fromEvent != null && fromEvent.id == journeyId) {
      widget.onCompleted?.call(fromEvent);
      _setExitInProgress(false);
      return;
    }

    final reconciled = _completedSelectedJourney(event);
    if (reconciled != null) {
      widget.onCompleted?.call(reconciled);
      _setExitInProgress(false);
      return;
    }

    // No usable journey on the event (older server): fall back to a fetch.
    () async {
      final journeyProvider = context.read<JourneyProvider>();
      // Validate from the returned entity; currentJourney survives a failed
      // fetch and would misreport which journey just ended.
      final journey = await journeyProvider.fetchJourneyById(journeyId);
      if (!mounted) return;

      if (journey != null && journey.id == journeyId) {
        widget.onCompleted?.call(journey);
      } else {
        // The journey really did end; we just could not load its summary (for
        // example the backend drops participation on completion and returns
        // 403). Exit anyway, and tell the host which journey ended so it can
        // release it — otherwise the stale selection keeps this layer mounted
        // and the "Finishing journey…" overlay never goes away.
        widget.onEndedWithoutSummary?.call(journeyId);
        widget.onExit?.call();
      }
      // If the host kept this layer mounted, do not leave a permanent spinner.
      _setExitInProgress(false);
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
    widget.controller.removeListener(_onMapControllerChanged);
    // Stop the peer-marker interpolation ticker before the map handle is gone.
    _stopInterpolationTicker();
    _navigationFrameTicker?.cancel();
    _navigationFrameTicker = null;
    // Stop the camera-follow GPS stream — independent of convoy coordination
    _cameraFollowSubscription?.cancel();
    _cameraFollowSubscription = null;
    // Drop any pending "retry the route when a fix arrives" listener.
    _cancelRouteLocationRetry();
    _cancelCanonicalRouteRetry();
    // Detach the polyline-trim listener before releasing the provider reference.
    _navigationProvider?.removeListener(_onNavigationProgress);
    // Stop the navigation layer — independent of convoy coordination.
    // Uses the cached reference because context.read<>() is unsafe here.
    _navigationProvider?.stopNavigation();
    // Deliberately no Mapbox cleanup here. `_disposed` is already true, so
    // `_canUseMap` is false and any channel call would be a no-op anyway — and
    // the drawings belong to the shell's persistent surface, not to this
    // widget. The shell removes them explicitly via LiveArtifactCleaner when
    // the user dismisses the journey.
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

    // Post-frame: align map-only state and handle server-driven events.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncActiveJourneyLayer();
      _handleArrivalEvent();
      _handleJourneyEndedEvent();
    });

    // Overlay chrome only — the map underneath belongs to the host shell.
    return Stack(
      children: [
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
                rosterMemberCount: _rosterMemberCount(currentJourney),
                connectionState: convoyConnectionState,
                onTap: _showConvoyBottomSheet,
                // Back collapses chrome; it must never reach the exit path,
                // which tears the journey down and clears the draft.
                onBack: widget.onBack,
                locationFailure: context
                    .watch<ConvoyProvider>()
                    .locationFailure,
                onRetryLocation: _retryLocation,
                journeyId: currentJourney.id,
                connectionAttemptId: context
                    .watch<ConvoyProvider>()
                    .connectionAttemptId,
                onReconnect: () => _reconnectConvoy(currentJourney.id),
                isReconnecting: _isReconnectingConvoy,
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
                  onToggleVoice: () => nav.setVoiceEnabled(!nav.isVoiceEnabled),
                );
              },
            ),
          ),

        Consumer<NavigationProvider>(
          builder: (context, navigation, _) {
            if (!navigation.offlineReroutePending) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: MediaQuery.of(context).padding.top + 176,
              left: 16,
              right: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE61A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFB020)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    'Offline — stay aware and return to the shown route. '
                    'A new road route will be calculated after reconnecting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            );
          },
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
                lastKnownProgress: navigation.lastKnownProgress,
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
        color: colors.surface,
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
                    style: TextStyle(
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
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.muted,
                        height: 1.3,
                      ),
                    )
                  else
                    Text(
                      'Ending journey…',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.muted,
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
                    color: colors.sunsetOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'End',
                    style: TextStyle(
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
          color: colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.routeTeal.withValues(alpha: 0.45),
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
                valueColor: AlwaysStoppedAnimation(colors.routeTeal),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Calculating route',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.ink,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
