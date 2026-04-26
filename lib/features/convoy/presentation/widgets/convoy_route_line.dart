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
  static const String _destinationSourceId = 'convoy-destination-source';

  /// Add convoy route visualization to the map
  static Future<void> addConvoyRoute(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
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

  /// Update convoy route with new snapshot data
  static Future<void> updateConvoyRoute(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    try {
      // Update route line source data
      await _updateRouteLineSource(mapboxMap, snapshot, currentUserId);
      
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

  /// Update route line source with new data
  static Future<void> _updateRouteLineSource(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    // Create route points
    final routePoints = _createRoutePoints(snapshot, currentUserId);
    
    if (routePoints.length < 2) {
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

    // Update source data
    try {
      // Remove existing source and re-add with new data
      await mapboxMap.style.removeStyleSource(_routeSourceId);
      await mapboxMap.style.addSource(GeoJsonSource(
        id: _routeSourceId,
        data: jsonEncode(geoJsonData),
      ));
    } catch (e) {
      // If source doesn't exist, create it
      await _addRouteLineSource(mapboxMap, snapshot, currentUserId);
    }
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
    
    // Get all convoy members (exclude current user)
    final members = snapshot.members.values
        .where((member) => member.userId != currentUserId)
        .toList();
    
    if (members.isEmpty) {
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
    try {
      // Remove existing markers
      await removeConvoyMarkers(mapboxMap);

      // Add member markers
      await _addMemberMarkersSource(mapboxMap, snapshot, currentUserId);
      await _addMemberMarkersLayer(mapboxMap);

      // Add destination marker
      await _addDestinationMarkerSource(mapboxMap, snapshot);
      await _addDestinationMarkerLayer(mapboxMap);

      print('✅ Convoy markers added');
    } catch (e) {
      print('❌ Failed to add convoy markers: $e');
    }
  }

  /// Remove convoy markers from the map
  static Future<void> removeConvoyMarkers(MapboxMap mapboxMap) async {
    try {
      // Remove member markers
      await mapboxMap.style.removeStyleLayer('convoy-members-layer');
      await mapboxMap.style.removeStyleSource(_membersSourceId);

      // Remove destination marker
      await mapboxMap.style.removeStyleLayer('convoy-destination-layer');
      await mapboxMap.style.removeStyleSource(_destinationSourceId);
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

    // Filter out current user
    final members = snapshot.members.values
        .where((member) => member.userId != currentUserId)
        .toList();

    for (int i = 0; i < members.length; i++) {
      final member = members[i];
      features.add({
        'type': 'Feature',
        'properties': {
          'userId': member.userId,
          'userIndex': i % 5, // Color index
          'isMoving': member.isMoving,
          'speed': member.speed ?? 0.0,
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

  /// Add member markers layer
  static Future<void> _addMemberMarkersLayer(MapboxMap mapboxMap) async {
    final circleLayer = CircleLayer(
      id: 'convoy-members-layer',
      sourceId: _membersSourceId,
      circleRadius: 12.0,
      circleColor: 0xFFE53E3E, // Default red, can be styled based on properties
      circleStrokeColor: 0xFFFFFFFF,
      circleStrokeWidth: 2.0,
      circleOpacity: 1.0,
    );

    await mapboxMap.style.addLayer(circleLayer);
  }

  /// Add destination marker source
  static Future<void> _addDestinationMarkerSource(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
  ) async {
    final geoJsonData = {
      'type': 'Feature',
      'properties': {
        'type': 'destination',
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [
          snapshot.destination.longitude,
          snapshot.destination.latitude,
        ],
      },
    };

    await mapboxMap.style.addSource(GeoJsonSource(
      id: _destinationSourceId,
      data: jsonEncode(geoJsonData),
    ));
  }

  /// Add destination marker layer
  static Future<void> _addDestinationMarkerLayer(MapboxMap mapboxMap) async {
    final circleLayer = CircleLayer(
      id: 'convoy-destination-layer',
      sourceId: _destinationSourceId,
      circleRadius: 16.0,
      circleColor: 0xFF000000, // Black for destination
      circleStrokeColor: 0xFFFFFFFF,
      circleStrokeWidth: 3.0,
      circleOpacity: 1.0,
    );

    await mapboxMap.style.addLayer(circleLayer);
  }
}