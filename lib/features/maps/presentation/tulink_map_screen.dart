import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/tulink_colors.dart';
import '../data/models/route_result_model.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'providers/map_provider.dart';
import '../../journeys/presentation/providers/journey_provider.dart';
import '../../journeys/domain/entities/journey.dart';
import '../../convoy/presentation/providers/convoy_provider.dart';
import '../../convoy/presentation/widgets/convoy_status_bar.dart';
import '../../convoy/presentation/widgets/convoy_bottom_sheet.dart';
import '../../convoy/presentation/widgets/convoy_metrics_bottom_sheet.dart';
import '../../convoy/presentation/widgets/journey_progress_card.dart';
import '../../convoy/presentation/widgets/driver_marker.dart';
import '../../convoy/presentation/widgets/convoy_route_line.dart';
import '../../convoy/domain/entities/convoy_snapshot.dart';
import '../../convoy/domain/entities/member_position.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../analytics/presentation/screens/journey_details_screen.dart';
import 'widgets/map_journey_overlay.dart';
import 'widgets/map_header_overlay.dart';
import 'widgets/turn_instruction_card.dart';
import 'providers/navigation_provider.dart';
import '../domain/entities/route_progress.dart';

class TulinkMapScreen extends StatefulWidget {
  const TulinkMapScreen({super.key});

  static const String routeName = '/mapview';

  @override
  State<TulinkMapScreen> createState() => _TulinkMapScreenState();
}

class _TulinkMapScreenState extends State<TulinkMapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  String? _activeJourneyId;
  bool _isConvoyCoordinationActive = false;
  ConvoySnapshot? _lastSnapshot;
  int _lastUpdateHash = 0;
  bool _disposed = false;

  /// True when it's safe to call the Mapbox channel — set false on dispose
  /// so async chains that resume after the widget is unmounted bail out
  /// instead of throwing PlatformException on a dead channel.
  bool get _canUseMap => !_disposed && mounted && _mapboxMap != null;

  // Camera always follows the user during an active journey — no toggle.
  StreamSubscription<geo.Position>? _cameraFollowSubscription;

  // Cached provider reference — safe to call in dispose() without a context.
  NavigationProvider? _navigationProvider;

  // True once the backend confirms the current user has arrived at the
  // destination (via `participant-arrived` WebSocket event).  Stops the
  // navigation layer and shows the arrival confirmation overlay.
  bool _currentUserHasArrived = false;

  // Progress card is collapsed by default so the map is visible while driving.
  // The user taps the pill to expand it when they need stats or the end button.
  bool _isProgressCardExpanded = false;

  /// True while a programmatic camera animation is in flight.
  bool _isProgrammaticCameraMove = false;

  /// Last segment index successfully written to the polyline source.
  /// Skips trim when the segment hasn't advanced.
  int? _lastTrimmedSegmentIndex;

  /// Last time we wrote to the polyline source. Throttles subsequent writes
  /// to at most one per 400 ms — the JSON encode + platform channel hop is
  /// expensive enough that doing it every GPS tick causes visible jitter.
  DateTime? _lastTrimAt;

  /// Last time we wrote to the snapped puck source. Higher update rate
  /// than the polyline (200 ms) because puck responsiveness is more
  /// perceptually important.
  DateTime? _lastPuckUpdateAt;

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = 
        await mapboxMap.annotations.createPointAnnotationManager();
    
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
          if (!_canUseMap) return;

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
            await _mapboxMap!.setCamera(CameraOptions(
              center: Point(
                  coordinates: Position(pos.longitude, pos.latitude)),
              bearing: pos.heading,
              zoom: 16.0,
              pitch: 45.0,
            ));
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

    try { await _mapboxMap!.style.removeStyleLayer(ringId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleLayer(dotId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(sourceId); } catch (_) {}

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
      await _mapboxMap!.style.addLayer(CircleLayer(
        id: ringId,
        sourceId: sourceId,
        circleRadius: 16.0,
        circleColor: 0x33E8002D,
        circleStrokeColor: 0xFFE8002D,
        circleStrokeWidth: 2.5,
        circleOpacity: 1.0,
      ));

      // Inner solid dot
      await _mapboxMap!.style.addLayer(CircleLayer(
        id: dotId,
        sourceId: sourceId,
        circleRadius: 8.0,
        circleColor: 0xFFE8002D,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.0,
        circleOpacity: 1.0,
      ));

      print('✅ Destination pin drawn at '
          '${journey.destination.latitude}, ${journey.destination.longitude}');
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
        locationSettings:
            const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      );
    } catch (e) {
      print('⚠️ Could not get position for camera fit — centering on destination');
      _isProgrammaticCameraMove = true;
      try {
        await _mapboxMap!.setCamera(CameraOptions(
          center: Point(
            coordinates: Position(
              journey.destination.longitude,
              journey.destination.latitude,
            ),
          ),
          zoom: 13.0,
        ));
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
      print('⚠️ cameraForCoordinateBounds failed: $e — falling back to destination center');
      _isProgrammaticCameraMove = true;
      try {
        await _mapboxMap!.setCamera(CameraOptions(
          center: Point(
            coordinates: Position(
              journey.destination.longitude,
              journey.destination.latitude,
            ),
          ),
          zoom: 13.0,
        ));
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
    final isCachedForThisDestination = route != null &&
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

    try { await _mapboxMap!.style.removeStyleLayer(lineId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleLayer(bgId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(sourceId); } catch (_) {}

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
      await _mapboxMap!.style.addLayer(LineLayer(
        id: bgId,
        sourceId: sourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidth: 8.0,
        lineColor: 0xFF000000,
        lineOpacity: 0.25,
      ));

      // Electric Red solid route line (roads → solid, not dashed)
      await _mapboxMap!.style.addLayer(LineLayer(
        id: lineId,
        sourceId: sourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidth: 5.0,
        lineColor: 0xFFE8002D,
        lineOpacity: 0.9,
      ));

      print('✅ Actual road route drawn: '
          '${route.distanceMetres.toStringAsFixed(0)}m, '
          '${route.steps.length} steps');
    } catch (e) {
      print('⚠️ Failed to draw actual route: $e');
    }

    // Hand the route to the navigation layer for turn-by-turn guidance.
    if (mounted) {
      await context.read<NavigationProvider>().startNavigation(
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
    _lastTrimmedSegmentIndex = null;
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
        locationSettings:
            const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('⚠️ Recenter: could not get position: $e');
      return;
    }

    // Prefer snapped position when available, mirroring _updateCameraFollow.
    final progress = _navigationProvider?.currentProgress;
    final centerLat = progress?.snappedLatitude ?? pos.latitude;
    final centerLng = progress?.snappedLongitude ?? pos.longitude;

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
    if (_mapboxMap == null) return;

    // Prefer snapped position when navigation is active so the camera centre
    // matches the custom puck. Falls back to raw GPS when navigation is
    // inactive or no progress snapshot exists yet.
    final progress = _navigationProvider?.currentProgress;
    final centerLat = progress?.snappedLatitude ?? position.latitude;
    final centerLng = progress?.snappedLongitude ?? position.longitude;

    _isProgrammaticCameraMove = true;
    try {
      await _mapboxMap!.setCamera(CameraOptions(
        center: Point(coordinates: Position(centerLng, centerLat)),
        bearing: position.heading,
        zoom: 16.0,
        pitch: 45.0,
      ));
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
      _trimRoutePolyline(progress.currentSegmentIndex);
      _drawSnappedPuck(progress);
    }
  }

  /// Update the GeoJSON source for the route polyline to show only the
  /// coordinates from [segmentIndex] onward — the portion of the route
  /// the driver still has to cover.
  Future<void> _trimRoutePolyline(int segmentIndex) async {
    if (!_canUseMap) return;
    const sourceId = 'actual-route-source';

    final route = _navigationProvider?.activeRoute;
    if (route == null || route.coordinates.length <= segmentIndex + 1) return;

    // Skip when the segment hasn't advanced — no visual change needed.
    if (_lastTrimmedSegmentIndex == segmentIndex) return;

    // Throttle to at most one write per 400 ms.
    final now = DateTime.now();
    if (_lastTrimAt != null &&
        now.difference(_lastTrimAt!).inMilliseconds < 400) {
      return;
    }

    final remaining = route.coordinates.sublist(segmentIndex);
    if (remaining.length < 2) return;

    _lastTrimAt = now;
    _lastTrimmedSegmentIndex = segmentIndex;

    print('✂️ Trim to segIdx=$segmentIndex, '
        'remaining=${remaining.length}/${route.coordinates.length}');

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
    const ringId  = 'snapped-puck-ring';
    const dotId   = 'snapped-puck-dot';

    if (progress == null) {
      try { await _mapboxMap!.style.removeStyleLayer(dotId);  } catch (_) {}
      try { await _mapboxMap!.style.removeStyleLayer(ringId); } catch (_) {}
      try { await _mapboxMap!.style.removeStyleSource(sourceId); } catch (_) {}
      // Restore the built-in puck now that the custom one is gone.
      try {
        await _mapboxMap!.location.updateSettings(
          LocationComponentSettings(enabled: true),
        );
      } catch (_) {}
      return;
    }

    // Throttle to ~5 Hz for active updates.
    final now = DateTime.now();
    if (_lastPuckUpdateAt != null &&
        now.difference(_lastPuckUpdateAt!).inMilliseconds < 200) {
      return;
    }
    _lastPuckUpdateAt = now;

    final geoJson = jsonEncode({
      'type': 'Feature',
      'properties': <String, dynamic>{},
      'geometry': {
        'type': 'Point',
        'coordinates': [progress.snappedLongitude, progress.snappedLatitude],
      },
    });

    try {
      final sourceExists =
          await _mapboxMap!.style.styleSourceExists(sourceId);
      if (!sourceExists) {
        // Swap off the built-in puck now that our snapped puck is taking over.
        // Prevents two overlapping dots during active navigation.
        try {
          await _mapboxMap!.location.updateSettings(
            LocationComponentSettings(enabled: false),
          );
        } catch (_) {}

        await _mapboxMap!.style.addSource(
          GeoJsonSource(id: sourceId, data: geoJson),
        );

        // Outer halo — soft white at 30% opacity, mirrors the system puck.
        await _mapboxMap!.style.addLayer(CircleLayer(
          id: ringId,
          sourceId: sourceId,
          circleRadius: 14.0,
          circleColor: 0xFFFFFFFF,
          circleOpacity: 0.3,
          circleStrokeWidth: 0,
        ));

        // Inner solid dot — Electric Red, Tu-Link branded.
        await _mapboxMap!.style.addLayer(CircleLayer(
          id: dotId,
          sourceId: sourceId,
          circleRadius: 7.0,
          circleColor: 0xFFE8002D,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2.5,
          circleOpacity: 1.0,
        ));
      } else {
        // Update geometry only — avoids recreating the layers on every tick.
        await _mapboxMap!.style.setStyleSourceProperty(
            sourceId, 'data', geoJson);
      }
    } catch (e) {
      print('⚠️ Failed to draw snapped puck: $e');
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
      
      // Enable the built-in puck so the user's position is visible from the
      // moment the map loads. _drawSnappedPuck will swap it off when active
      // navigation produces a snapped position, then restore it on cleanup.
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
      ));
      
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

    // Get convoy snapshot filtered to exclude current user
    final convoySnapshot = currentUserId != null
        ? convoyProvider.getDisplaySnapshot(currentUserId)
        : convoyProvider.snapshot;

    // Generate a hash to check if the snapshot has actually changed
    final currentHash = _generateSnapshotHash(convoySnapshot);

    // Only update if the snapshot has changed
    if (currentHash != _lastUpdateHash) {
      _lastUpdateHash = currentHash;
      _lastSnapshot = convoySnapshot;

      if (convoySnapshot != null && currentUserId != null) {
        await ConvoyRouteLine.addConvoyMarkers(_mapboxMap!, convoySnapshot, currentUserId);
        print('✅ Updated convoy markers: ${convoySnapshot.members.length} members');
      } else {
        await ConvoyRouteLine.removeConvoyMarkers(_mapboxMap!);
        print('✅ Removed convoy visualization');
        _lastSnapshot = null;
      }
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
      _cameraFollowSubscription ??= geo.Geolocator.getPositionStream(
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
            // TODO: Center map on member position
            Navigator.pop(context);
          },
          onClose: () => Navigator.pop(context),
        ),
      );
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
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.blue),
              title: const Text('Refresh Convoy Data', style: TextStyle(color: Colors.white)),
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
              title: const Text('Reconnect to Convoy', style: TextStyle(color: Colors.white)),
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
              title: const Text('Clear Error', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                convoyProvider.clearError();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop, color: Colors.red),
              title: const Text('End Journey', style: TextStyle(color: Colors.red)),
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
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();

    // Capture before any await — providers may clear this during the async gap.
    final journeyId =
        journeyProvider.currentJourney?.id ?? _activeJourneyId;

    if (journeyId == null) {
      // Journey already cleared externally — just navigate home cleanly.
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
      return;
    }

    await _navigationProvider?.stopNavigation();
    await convoyProvider.stopCoordination();

    final success = await journeyProvider.endJourney(journeyId);

    if (!context.mounted) return;

    if (success) {
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
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } else {
      // API failure — journey is likely already COMPLETED on the server.
      // Navigate home rather than leaving the user stuck on the map screen.
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    }
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
    if (!mounted) return;
    final convoyProvider = context.read<ConvoyProvider>();
    final event = convoyProvider.lastJourneyEndedEvent;
    if (event == null) return;

    // Consume up-front so a rebuild triggered by the async fetch below
    // doesn't re-enter this handler.
    convoyProvider.consumeJourneyEndedEvent();
    final journeyId = event.journeyId;

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
            builder: (context) => JourneyDetailsScreen(
              journey: journey,
              showDoneButton: true,
            ),
          ),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(
            '/home', (route) => false);
      }
    }();
  }

  /// Show confirmation dialog for ending journey
  void _showEndJourneyConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('End Journey?', style: TextStyle(color: Colors.white)),
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
            child: const Text('End Journey', style: TextStyle(color: Colors.red)),
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
              const SnackBar(content: Text('End journey functionality coming soon!')),
            );
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _mapboxMap = null;
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
    final convoyConnectionState = context.watch<ConvoyProvider>().connectionState;
    final convoyError = context.watch<ConvoyProvider>().errorMessage;
    // Watching these triggers rebuilds when server events arrive so the
    // post-frame callbacks can react immediately.
    context.watch<ConvoyProvider>().lastJourneyEndedEvent;
    context.watch<ConvoyProvider>().lastArrivalEvent;
    final currentUserId = context.watch<AuthProvider>().user?.id ?? '';
    final isLeader = currentJourney != null &&
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
              key: const ValueKey('mapbox_map'),
              onMapCreated: _onMapCreated,
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
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: _showConvoyBottomSheet,
                onLongPress: _showConvoyManagementOptions,
                child: ConvoyStatusBar(
                  snapshot: convoySnapshot,
                  connectionState: convoyConnectionState,
                  onTap: _showConvoyBottomSheet,
                  onBack: () => Navigator.of(context).pushNamedAndRemoveUntil(
                    '/home',
                    (route) => false,
                  ),
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
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 0,
              right: 0,
              child: Consumer<MapProvider>(
                builder: (context, mapProvider, _) {
                  if (!mapProvider.isFetchingRoute) return const SizedBox.shrink();
                  return const _RouteLoadingPill();
                },
              ),
            ),

          // Map Header - Top Overlay (when no active journey)
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.topCenter,
              child: MapHeaderOverlay(),
            ),

          // Journey Progress Card - Bottom Overlay (collapsed pill by default)
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.bottomCenter,
              child: JourneyProgressCard(
                journey: currentJourney,
                convoySnapshot: convoySnapshot,
                currentUserId: currentUserId,
                isLeader: isLeader,
                onEndJourney: _showEndJourneyConfirmation,
                isExpanded: _isProgressCardExpanded,
                onToggleExpanded: () =>
                    setState(() => _isProgressCardExpanded = !_isProgressCardExpanded),
              ),
            ),
            
          // Map Bottom Bar - Show when no active journey
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.bottomCenter,
              child: MapJourneyOverlay(),
            ),

          // Recenter button — active journey.
          // Shifts up by the card-expansion delta (182 px) so it always clears
          // the expanded card header.
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
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
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
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
                    const Icon(Icons.error_outline, color: Colors.white, size: 20),
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
                      icon: const Icon(Icons.settings, color: Colors.white, size: 20),
                      tooltip: 'Convoy Management',
                    ),
                  ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
