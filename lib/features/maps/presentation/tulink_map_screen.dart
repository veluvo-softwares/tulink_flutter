import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
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

  // Camera follow mode — active by default once a journey starts
  bool _isFollowMode = true;
  StreamSubscription<geo.Position>? _cameraFollowSubscription;

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
        await _drawSoloRouteLine(currentJourney);
        // Fetch the real road route — placeholder stays until it arrives
        unawaited(_drawActualRoute(currentJourney));
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

  /// Draw a straight-line route from the user's current GPS position to the
  /// destination. Acts as a visual placeholder for solo journeys until convoy
  /// members join and [ConvoyRouteLine] takes over.
  Future<void> _drawSoloRouteLine(Journey journey) async {
    if (_mapboxMap == null) return;
    const sourceId = 'solo-route-source';
    const bgId = 'solo-route-bg';
    const lineId = 'solo-route-line';

    try { await _mapboxMap!.style.removeStyleLayer(lineId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleLayer(bgId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(sourceId); } catch (_) {}

    geo.Position? pos;
    try {
      pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
    } catch (e) {
      print('⚠️ Could not get current position for route line: $e');
      return;
    }

    try {
      final geoJson = jsonEncode({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [pos.longitude, pos.latitude],
            [journey.destination.longitude, journey.destination.latitude],
          ],
        },
      });

      await _mapboxMap!.style.addSource(
        GeoJsonSource(id: sourceId, data: geoJson),
      );

      // Shadow line
      await _mapboxMap!.style.addLayer(LineLayer(
        id: bgId,
        sourceId: sourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidth: 8.0,
        lineColor: 0xFF000000,
        lineOpacity: 0.2,
      ));

      // Electric Red dashed route
      await _mapboxMap!.style.addLayer(LineLayer(
        id: lineId,
        sourceId: sourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidth: 4.0,
        lineColor: 0xFFE8002D,
        lineOpacity: 0.85,
        lineDasharray: [2.0, 1.5],
      ));

      print('✅ Solo route line drawn from current position to destination');
    } catch (e) {
      print('⚠️ Failed to draw solo route line: $e');
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
      await _mapboxMap!.setCamera(CameraOptions(
        center: Point(
          coordinates: Position(
            journey.destination.longitude,
            journey.destination.latitude,
          ),
        ),
        zoom: 13.0,
      ));
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
      await _mapboxMap!.setCamera(camera);
      print('✅ Camera fitted to journey bounds');
    } catch (e) {
      print('⚠️ cameraForCoordinateBounds failed: $e — falling back to destination center');
      await _mapboxMap!.setCamera(CameraOptions(
        center: Point(
          coordinates: Position(
            journey.destination.longitude,
            journey.destination.latitude,
          ),
        ),
        zoom: 13.0,
      ));
    }
  }

  /// Fetch the road-following route from the backend and draw it on the map.
  /// The straight-line placeholder from [_drawSoloRouteLine] stays visible
  /// until this succeeds, then is replaced. Fails silently — placeholder stays.
  Future<void> _drawActualRoute(Journey journey) async {
    if (_mapboxMap == null) return;

    // Get current GPS position as route origin
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

    // Fetch route from backend (NestJS → Mapbox Directions, Redis cached)
    if (!mounted) return;
    final mapProvider = context.read<MapProvider>();
    final route = await mapProvider.fetchRoute(
      originLat: pos.latitude,
      originLng: pos.longitude,
      destLat: journey.destination.latitude,
      destLng: journey.destination.longitude,
    );

    if (route == null || !mounted || _mapboxMap == null) return;

    // Remove the straight-line placeholder layers
    const soloSourceId = 'solo-route-source';
    const soloBgId = 'solo-route-bg';
    const soloLineId = 'solo-route-line';
    try { await _mapboxMap!.style.removeStyleLayer(soloLineId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleLayer(soloBgId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(soloSourceId); } catch (_) {}

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
  }

  /// Track the user's current position with bearing and a 3D driving tilt.
  Future<void> _updateCameraFollow(geo.Position position) async {
    if (!_isFollowMode || _mapboxMap == null) return;

    await _mapboxMap!.setCamera(CameraOptions(
      center: Point(coordinates: Position(
        position.longitude,
        position.latitude,
      )),
      bearing: position.heading,
      zoom: 16.0,
      pitch: 45.0, // 3D driving tilt
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh markers only when provider dependencies actually change,
    // rather than on every build().
    if (_mapboxMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateMarkers();
      });
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
      
      // Enable user location component (blue dot)
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
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
      final isFirstUpdate = _lastSnapshot == null;
      _lastSnapshot = convoySnapshot;

      // Once real convoy members are present, remove the solo placeholder
      // route so it does not visually conflict with the convoy route.
      if (convoySnapshot != null && convoySnapshot.members.isNotEmpty) {
        try { await _mapboxMap!.style.removeStyleLayer('solo-route-line'); } catch (_) {}
        if (!_canUseMap) return;
        try { await _mapboxMap!.style.removeStyleLayer('solo-route-bg'); } catch (_) {}
        if (!_canUseMap) return;
        try { await _mapboxMap!.style.removeStyleSource('solo-route-source'); } catch (_) {}
        if (!_canUseMap) return;
      }

      if (convoySnapshot != null && currentUserId != null) {
        // Update convoy visualization with route line and member markers
        if (isFirstUpdate) {
          await ConvoyRouteLine.addConvoyMarkers(_mapboxMap!, convoySnapshot, currentUserId);
          if (!_canUseMap) return;
          await ConvoyRouteLine.addConvoyRoute(_mapboxMap!, convoySnapshot, currentUserId);
        } else {
          await ConvoyRouteLine.addConvoyMarkers(_mapboxMap!, convoySnapshot, currentUserId);
          if (!_canUseMap) return;
          await ConvoyRouteLine.updateConvoyRoute(_mapboxMap!, convoySnapshot, currentUserId);
        }

        print('✅ Updated convoy markers: ${convoySnapshot.members.length} members');
      } else {
        await ConvoyRouteLine.removeConvoyMarkers(_mapboxMap!);
        if (!_canUseMap) return;
        await ConvoyRouteLine.removeConvoyRoute(_mapboxMap!);
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

  /// End the journey and stop convoy coordination
  Future<void> _endJourney() async {
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();
    
    // Stop convoy coordination
    convoyProvider.stopCoordination();
    
    // End the journey (set status to completed)
    final currentJourney = journeyProvider.currentJourney;
    if (currentJourney != null) {
      final success = await journeyProvider.endJourney(currentJourney.id);
      
      if (success && context.mounted) {
        // Get the updated journey with completed status
        final completedJourney = journeyProvider.currentJourney;
        
        if (completedJourney != null) {
          // Navigate to journey details screen with Done button
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => JourneyDetailsScreen(
                journey: completedJourney,
                showDoneButton: true,
              ),
            ),
          );
        } else {
          // Fallback: navigate to home if no journey data
          Navigator.of(context).pop();
        }
      } else {
        // Show error message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to end journey. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
    // Don't stop convoy coordination when leaving map screen
    // The journey should continue in the background
    // Only stop convoy coordination when journey is actually ended
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to journey and convoy changes to update markers
    final currentJourney = context.watch<JourneyProvider>().currentJourney;
    final convoySnapshot = context.watch<ConvoyProvider>().snapshot;
    final convoyConnectionState = context.watch<ConvoyProvider>().connectionState;
    final convoyError = context.watch<ConvoyProvider>().errorMessage;
    final currentUserId = context.watch<AuthProvider>().user?.id ?? '';
    final isLeader = currentJourney != null &&
        currentUserId.isNotEmpty &&
        currentJourney.leaderId == currentUserId;
    
    // Marker updates are driven by didChangeDependencies(), not build().

    // Check convoy coordination state. Guard with mounted because the
    // callback fires next frame — by then the widget can be disposed
    // (e.g. AuthProvider.onAuthLost flipped isSignedIn after a token
    // refresh failed and HomePage swapped MainNavigationScreen for
    // AuthScreen), and reading context on a defunct State throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAndStartConvoyCoordination();
    });

    return Scaffold(
      body: Stack(
        children: [
          // Standard Mapbox Map — panning the map disables follow mode
          GestureDetector(
            onPanStart: (_) {
              if (_isFollowMode) setState(() => _isFollowMode = false);
            },
            child: RepaintBoundary(
              child: MapWidget(
                key: const ValueKey('mapbox_map'),
                onMapCreated: _onMapCreated,
                styleUri: MapboxStyles.DARK,
                cameraOptions: CameraOptions(
                  center: Point(
                    coordinates: Position(36.8219, -1.2921), // Nairobi
                  ),
                  zoom: 10, // Zoom in more for convoy coordination
                ),
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
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          
          // Map Header - Top Overlay (when no active journey)
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.topCenter,
              child: MapHeaderOverlay(),
            ),

          // Journey Progress Card - Bottom Overlay
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.bottomCenter,
              child: JourneyProgressCard(
                journey: currentJourney,
                convoySnapshot: convoySnapshot,
                currentUserId: currentUserId,
                isLeader: isLeader,
                onEndJourney: _showEndJourneyConfirmation,
              ),
            ),
            
          // Map Bottom Bar - Show when no active journey
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.bottomCenter,
              child: MapJourneyOverlay(),
            ),

          // Follow Mode Toggle - bottom right, above the progress card
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Positioned(
              bottom: 220,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _isFollowMode = !_isFollowMode),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isFollowMode
                          ? const Color(0xFFE8002D)
                          : Colors.grey.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isFollowMode
                        ? Icons.navigation
                        : Icons.navigation_outlined,
                    color: _isFollowMode
                        ? const Color(0xFFE8002D)
                        : Colors.grey,
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
      floatingActionButton: (currentJourney != null && 
          currentJourney.status == JourneyStatus.ACTIVE && 
          convoySnapshot != null &&
          convoySnapshot.members.isNotEmpty) 
        ? FloatingActionButton(
            onPressed: _showConvoyMetricsBottomSheet,
            backgroundColor: const Color(0xFFE53E3E),
            child: const Icon(
              Icons.analytics_outlined,
              color: Colors.white,
            ),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
