import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';

/// Widget for displaying convoy route visualization with dotted lines
/// Shows the path between convoy members and destination
class ConvoyRouteLine {
  static const String _routeSourceId = 'convoy-route-source';
  static const String _routeLayerId = 'convoy-route-layer';
  static const String _membersSourceId = 'convoy-members-source';

  /// Add convoy route visualization to the map
  static Future<void> addConvoyRoute(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    // Bail if destination coordinates are invalid (0,0 fallback)
    if (snapshot.destination.latitude == 0.0 &&
        snapshot.destination.longitude == 0.0) {
      print('⚠️ Skipping convoy rendering — destination coordinates are (0,0)');
      return;
    }

    try {
      // Remove existing route if any
      await removeConvoyRoute(mapboxMap);

      // Create route line between members and destination
      await _addRouteLineSource(mapboxMap, snapshot, currentUserId);
      
      // Add route line layer
      await _addRouteLineLayer(mapboxMap);
      
      print('✅ Convoy route visualization added');
    } catch (e) {
      print('❌ Failed to add convoy route: $e');
    }
  }

  /// Remove convoy route visualization from the map
  static Future<void> removeConvoyRoute(MapboxMap mapboxMap) async {
    try {
      // Remove layers (main line and background)
      await mapboxMap.style.removeStyleLayer(_routeLayerId);
      await mapboxMap.style.removeStyleLayer('${_routeLayerId}-background');
      
      // Remove sources
      await mapboxMap.style.removeStyleSource(_routeSourceId);
    } catch (e) {
      // Ignore errors for non-existent layers/sources
      print('⚠️ Error removing convoy route (may not exist): $e');
    }
  }

  /// Update convoy route with new snapshot data.
  ///
  /// Mapbox requires layers to be removed before their source can be removed,
  /// so updates go through the full remove → add cycle. [removeConvoyRoute]
  /// is idempotent — it silently ignores missing layers/sources.
  static Future<void> updateConvoyRoute(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    if (snapshot.destination.latitude == 0.0 &&
        snapshot.destination.longitude == 0.0) {
      print('⚠️ Skipping convoy route update — destination is (0,0)');
      return;
    }

    try {
      await removeConvoyRoute(mapboxMap);
      await _addRouteLineSource(mapboxMap, snapshot, currentUserId);
      await _addRouteLineLayer(mapboxMap);
      print('✅ Convoy route updated with ${snapshot.members.length} members');
    } catch (e) {
      print('❌ Failed to update convoy route: $e');
    }
  }

  /// Add route line data source
  static Future<void> _addRouteLineSource(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    // Create route points
    final routePoints = _createRoutePoints(snapshot, currentUserId);
    
    if (routePoints.length < 2) {
      print('⚠️ Not enough points to create route line');
      return;
    }

    // Create GeoJSON LineString
    final geoJsonData = {
      'type': 'Feature',
      'properties': {},
      'geometry': {
        'type': 'LineString',
        'coordinates': routePoints,
      },
    };

    // Add source
    await mapboxMap.style.addSource(GeoJsonSource(
      id: _routeSourceId,
      data: jsonEncode(geoJsonData),
    ));
  }

  /// Add route line layer with enhanced Uber-style dotted visualization
  static Future<void> _addRouteLineLayer(MapboxMap mapboxMap) async {
    // Add background line for better visibility
    final backgroundLineLayer = LineLayer(
      id: '${_routeLayerId}-background',
      sourceId: _routeSourceId,
      lineCap: LineCap.ROUND,
      lineJoin: LineJoin.ROUND,
      lineWidth: 8.0,
      lineColor: 0xFF000000, // Black background
      lineOpacity: 0.3,
    );

    // Add main convoy route line with dotted pattern
    final mainLineLayer = LineLayer(
      id: _routeLayerId,
      sourceId: _routeSourceId,
      lineCap: LineCap.ROUND,
      lineJoin: LineJoin.ROUND,
      lineWidth: 5.0,
      lineColor: 0xFFE53E3E, // Red color matching convoy theme
      lineOpacity: 0.9,
      lineDasharray: [3.0, 2.0], // More prominent dotted pattern
    );

    // Add layers in order (background first, then main line)
    await mapboxMap.style.addLayer(backgroundLineLayer);
    await mapboxMap.style.addLayer(mainLineLayer);
  }

  /// Create route points for convoy visualization
  /// Creates a simplified route showing convoy progress toward destination
  static List<List<double>> _createRoutePoints(
    ConvoySnapshot snapshot,
    String currentUserId,
  ) {
    final points = <List<double>>[];
    
    // Get all convoy members from filtered snapshot (current user already excluded by provider)
    final members = snapshot.members.values.toList();
    
    if (members.isEmpty) {
      // For solo journeys with no position yet, create route from destination
      points.add([snapshot.destination.longitude, snapshot.destination.latitude]);
      return points;
    }

    // Sort members by distance to destination (closest first)
    members.sort((a, b) => _getDistanceToDestination(a, snapshot.destination)
        .compareTo(_getDistanceToDestination(b, snapshot.destination)));

    // Create a convoy trail: start from the furthest member, connect through others, end at destination
    // This creates a more realistic convoy route visualization
    if (members.length == 1) {
      // Single member: direct line to destination
      points.add([members.first.longitude, members.first.latitude]);
      points.add([snapshot.destination.longitude, snapshot.destination.latitude]);
    } else {
      // Multiple members: create convoy path from furthest to closest to destination
      final sortedByDistance = members.reversed.toList(); // Furthest first
      
      // Add all member positions in convoy order
      for (final member in sortedByDistance) {
        points.add([member.longitude, member.latitude]);
      }
      
      // Add destination as final point
      points.add([snapshot.destination.longitude, snapshot.destination.latitude]);
    }

    return points;
  }

  /// Calculate distance to destination for sorting
  static double _getDistanceToDestination(
    MemberPosition member,
    ConvoyDestination destination,
  ) {
    return _calculateDistance(
      member.latitude,
      member.longitude,
      destination.latitude,
      destination.longitude,
    );
  }

  /// Calculate distance between two points using Haversine formula
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    
    final double lat1Rad = lat1 * math.pi / 180;
    final double lat2Rad = lat2 * math.pi / 180;
    final double deltaLatRad = (lat2 - lat1) * math.pi / 180;
    final double deltaLonRad = (lon2 - lon1) * math.pi / 180;
    
    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLonRad / 2) * math.sin(deltaLonRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Create convoy member markers on the map
  static Future<void> addConvoyMarkers(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    // Bail if destination coordinates are invalid (0,0 fallback)
    if (snapshot.destination.latitude == 0.0 &&
        snapshot.destination.longitude == 0.0) {
      print('⚠️ Skipping convoy rendering — destination coordinates are (0,0)');
      return;
    }

    try {
      // Remove existing markers
      await removeConvoyMarkers(mapboxMap);

      // Add member markers
      await _addMemberMarkersSource(mapboxMap, snapshot, currentUserId);
      await _addMemberMarkersLayer(mapboxMap);

      // Destination marker is drawn by _drawDestinationPin in tulink_map_screen.dart
      // from static Journey data — no duplicate destination layer is needed here.

      print('✅ Convoy member markers added');
    } catch (e) {
      print('❌ Failed to add convoy markers: $e');
    }
  }

  /// Remove convoy markers from the map
  static Future<void> removeConvoyMarkers(MapboxMap mapboxMap) async {
    try {
      await mapboxMap.style.removeStyleLayer('convoy-members-label-layer');
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
    try {
      await mapboxMap.style.removeStyleLayer('convoy-members-layer');
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
    try {
      await mapboxMap.style.removeStyleLayer('convoy-members-heading-layer');
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
    try {
      await mapboxMap.style.removeStyleSource(_membersSourceId);
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
  }

  /// Add member markers source
  static Future<void> _addMemberMarkersSource(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    final features = <Map<String, dynamic>>[];

    // Get all convoy members from filtered snapshot (current user already excluded by provider)  
    final members = snapshot.members.values.toList();

    for (int i = 0; i < members.length; i++) {
      final member = members[i];
      features.add({
        'type': 'Feature',
        'properties': {
          'userId': member.userId,
          'userIndex': i % 5,
          'isMoving': member.isMoving,
          'speed': member.speed ?? 0.0,
          'initials': _initialsForUser(member.userId),
          'heading': member.heading ?? 0.0,
          'status': member.memberStatus,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [member.longitude, member.latitude],
        },
      });
    }

    final geoJsonData = {
      'type': 'FeatureCollection',
      'features': features,
    };

    await mapboxMap.style.addSource(GeoJsonSource(
      id: _membersSourceId,
      data: jsonEncode(geoJsonData),
    ));
  }

  /// Extract 2-character initials from a userId. Falls back to a single
  /// letter if the userId is shorter. Real names should be threaded
  /// through here in a future iteration via a user-display-name lookup
  /// service; for now, the userId initials are the consistent identifier.
  static String _initialsForUser(String userId) {
    final clean = userId.trim();
    if (clean.length >= 2) return clean.substring(0, 2).toUpperCase();
    if (clean.isNotEmpty) return clean.substring(0, 1).toUpperCase();
    return '?';
  }

  /// Add member marker layers. Three layers stacked per member feature:
  /// heading arrow underneath, coloured dot in the middle, initials label
  /// on top.
  ///
  /// Colours are driven by each feature's `status` property using Mapbox
  /// match expressions, so a single layer renders five different colour
  /// states without needing five separate layers.
  static Future<void> _addMemberMarkersLayer(MapboxMap mapboxMap) async {
    // ── Heading arrow layer ──────────────────────────────────────────
    //
    // Rendered as a Mapbox built-in arrow icon, rotated by `heading`,
    // sitting just below the dot so its base is occluded and only the
    // tip pokes out as a directional indicator.
    try {
      await mapboxMap.style.addLayer(SymbolLayer(
        id: 'convoy-members-heading-layer',
        sourceId: _membersSourceId,
        iconImage: 'triangle-stroked-15',
        iconSize: 1.4,
        iconRotateExpression: ['get', 'heading'],
        iconRotationAlignment: IconRotationAlignment.MAP,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconOffset: [0.0, -1.8],
      ));
    } catch (e) {
      print('⚠️ Failed to add heading layer: $e');
    }

    // ── Member dot layer ─────────────────────────────────────────────
    //
    // circleColor is a match expression driven by each feature's `status`
    // property. Falls back to Electric Red for unknown statuses.
    try {
      await mapboxMap.style.addLayer(CircleLayer(
        id: 'convoy-members-layer',
        sourceId: _membersSourceId,
        circleRadius: 14.0,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.5,
        circleOpacity: 1.0,
        circleColorExpression: [
          'match',
          ['get', 'status'],
          'MOVING', '#38A169',
          'STOPPED', '#3182CE',
          'LAG', '#DD6B20',
          'ARRIVED', '#0D7C66',
          'OFFLINE', '#718096',
          '#E8002D',
        ],
      ));
    } catch (e) {
      print('⚠️ Failed to add members dot layer: $e');
    }

    // ── Initials label layer ─────────────────────────────────────────
    //
    // The initials sit centred on the dot.
    try {
      await mapboxMap.style.addLayer(SymbolLayer(
        id: 'convoy-members-label-layer',
        sourceId: _membersSourceId,
        textFieldExpression: ['get', 'initials'],
        textFont: ['DIN Pro Bold', 'Arial Unicode MS Bold'],
        textSize: 11.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.0,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ));
    } catch (e) {
      print('⚠️ Failed to add label layer: $e');
    }
  }

}