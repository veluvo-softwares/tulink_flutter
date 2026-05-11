import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../domain/entities/directions_route.dart';
import '../../../../core/utils/polyline_decoder.dart';

/// Service for managing route polylines on the map
class RoutePolylineOverlay {
  static const String _primaryRouteLayerId = 'primary_route_line';
  static const String _primaryRouteSourceId = 'primary_route_source';
  static const String _alternativeRouteLayerId = 'alternative_route_line';
  static const String _alternativeRouteSourceId = 'alternative_route_source';

  /// Add primary route polyline to the map
  static Future<void> addPrimaryRoute(
    MapboxMap mapboxMap,
    DirectionsRoute route, {
    Color color = const Color(0xFF007AFF),
    double width = 6.0,
  }) async {
    try {
      // Remove existing primary route first
      await removePrimaryRoute(mapboxMap);

      // Decode polyline geometry
      final coordinates = PolylineDecoder.decode(route.geometry);
      
      if (coordinates.isEmpty) {
        print('⚠️ No coordinates found in route geometry');
        return;
      }

      // Create GeoJSON LineString
      final geoJsonMap = {
        "type": "Feature",
        "properties": {},
        "geometry": {
          "type": "LineString",
          "coordinates": coordinates.map((coord) => [coord.longitude, coord.latitude]).toList(),
        },
      };
      final geoJsonData = jsonEncode(geoJsonMap);
      
      final geoJsonSource = GeoJsonSource(
        id: _primaryRouteSourceId,
        data: geoJsonData,
      );

      // Add source to map
      await mapboxMap.style.addSource(geoJsonSource);

      // Create line layer
      final lineLayer = LineLayer(
        id: _primaryRouteLayerId,
        sourceId: _primaryRouteSourceId,
        lineColor: color.value,
        lineWidth: width,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineOpacity: 0.8,
      );

      // Add layer to map
      await mapboxMap.style.addLayer(lineLayer);

      print('✅ Primary route added with ${coordinates.length} coordinates');
    } catch (e) {
      print('❌ Failed to add primary route: $e');
    }
  }

  /// Add alternative routes to the map
  static Future<void> addAlternativeRoutes(
    MapboxMap mapboxMap,
    List<DirectionsRoute> routes, {
    Color color = const Color(0xFF8E8E93),
    double width = 4.0,
  }) async {
    try {
      // Remove existing alternative routes first
      await removeAlternativeRoutes(mapboxMap);

      if (routes.isEmpty) return;

      // Skip first route (primary) and take alternatives
      final alternativeRoutes = routes.skip(1).toList();
      if (alternativeRoutes.isEmpty) return;

      for (int i = 0; i < alternativeRoutes.length; i++) {
        final route = alternativeRoutes[i];
        final coordinates = PolylineDecoder.decode(route.geometry);
        
        if (coordinates.isEmpty) continue;

        final sourceId = '${_alternativeRouteSourceId}_$i';
        final layerId = '${_alternativeRouteLayerId}_$i';

        // Create GeoJSON source for this alternative
        final geoJsonMap = {
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates": coordinates.map((coord) => [coord.longitude, coord.latitude]).toList(),
          },
        };
        final geoJsonData = jsonEncode(geoJsonMap);
        
        final geoJsonSource = GeoJsonSource(
          id: sourceId,
          data: geoJsonData,
        );

        await mapboxMap.style.addSource(geoJsonSource);

        // Create line layer for this alternative
        final lineLayer = LineLayer(
          id: layerId,
          sourceId: sourceId,
          lineColor: color.value,
          lineWidth: width,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineOpacity: 0.6,
        );

        await mapboxMap.style.addLayer(lineLayer);
      }

      print('✅ Added ${alternativeRoutes.length} alternative routes');
    } catch (e) {
      print('❌ Failed to add alternative routes: $e');
    }
  }

  /// Update primary route with new data
  static Future<void> updatePrimaryRoute(
    MapboxMap mapboxMap,
    DirectionsRoute route, {
    Color color = const Color(0xFF007AFF),
    double width = 6.0,
  }) async {
    // For simplicity, remove and re-add the route
    // In a production app, you might want to just update the source data
    await addPrimaryRoute(mapboxMap, route, color: color, width: width);
  }

  /// Remove primary route from map
  static Future<void> removePrimaryRoute(MapboxMap mapboxMap) async {
    try {
      // Check if layer exists before removing
      try {
        await mapboxMap.style.removeStyleLayer(_primaryRouteLayerId);
      } catch (e) {
        // Layer doesn't exist, that's fine
      }

      // Check if source exists before removing
      try {
        await mapboxMap.style.removeStyleSource(_primaryRouteSourceId);
      } catch (e) {
        // Source doesn't exist, that's fine
      }
    } catch (e) {
      print('❌ Failed to remove primary route: $e');
    }
  }

  /// Remove all alternative routes from map
  static Future<void> removeAlternativeRoutes(MapboxMap mapboxMap) async {
    try {
      // Remove up to 5 alternative routes (reasonable limit)
      for (int i = 0; i < 5; i++) {
        final layerId = '${_alternativeRouteLayerId}_$i';
        final sourceId = '${_alternativeRouteSourceId}_$i';

        try {
          await mapboxMap.style.removeStyleLayer(layerId);
        } catch (e) {
          // Layer doesn't exist, continue
        }

        try {
          await mapboxMap.style.removeStyleSource(sourceId);
        } catch (e) {
          // Source doesn't exist, continue
        }
      }
    } catch (e) {
      print('❌ Failed to remove alternative routes: $e');
    }
  }

  /// Remove all route overlays
  static Future<void> removeAllRoutes(MapboxMap mapboxMap) async {
    await removePrimaryRoute(mapboxMap);
    await removeAlternativeRoutes(mapboxMap);
    print('✅ All route overlays removed');
  }

  /// Fit map camera to route bounds
  static Future<void> fitCameraToRoute(
    MapboxMap mapboxMap,
    DirectionsRoute route, {
    EdgeInsets padding = const EdgeInsets.all(50),
  }) async {
    try {
      final coordinates = PolylineDecoder.decode(route.geometry);
      
      if (coordinates.isEmpty) {
        print('⚠️ No coordinates to fit camera to');
        return;
      }

      // Calculate bounds
      double minLat = coordinates.first.latitude;
      double maxLat = coordinates.first.latitude;
      double minLng = coordinates.first.longitude;
      double maxLng = coordinates.first.longitude;

      for (final coord in coordinates) {
        minLat = coord.latitude < minLat ? coord.latitude : minLat;
        maxLat = coord.latitude > maxLat ? coord.latitude : maxLat;
        minLng = coord.longitude < minLng ? coord.longitude : minLng;
        maxLng = coord.longitude > maxLng ? coord.longitude : maxLng;
      }

      // Calculate center and zoom level
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;
      
      // Simple zoom calculation (you may want to adjust this)
      final zoom = 14.0 - (latDiff > lngDiff ? latDiff : lngDiff) * 100;
      final clampedZoom = zoom.clamp(8.0, 18.0);

      // Set camera to center of route
      await mapboxMap.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          zoom: clampedZoom,
        ),
      );

      print('✅ Camera fitted to route bounds');
    } catch (e) {
      print('❌ Failed to fit camera to route: $e');
    }
  }

  /// Get route color based on traffic conditions or route type
  static Color getRouteColor({
    bool isPrimary = true,
    bool hasTraffic = false,
    double? trafficLevel,
  }) {
    if (isPrimary) {
      if (hasTraffic && trafficLevel != null) {
        // Color based on traffic level (0.0 = green, 1.0 = red)
        if (trafficLevel < 0.3) {
          return const Color(0xFF34C759); // Green - light traffic
        } else if (trafficLevel < 0.7) {
          return const Color(0xFFFF9500); // Orange - moderate traffic
        } else {
          return const Color(0xFFFF3B30); // Red - heavy traffic
        }
      }
      return const Color(0xFF007AFF); // Default blue for primary route
    } else {
      return const Color(0xFF8E8E93); // Gray for alternative routes
    }
  }
}
