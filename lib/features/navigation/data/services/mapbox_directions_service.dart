import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../../journeys/domain/entities/journey.dart';
import '../../domain/entities/directions_route.dart';
import '../models/navigation_step.dart';

/// Service for interacting with Mapbox Directions API
class MapboxDirectionsService {
  MapboxDirectionsService({
    required Dio dio,
    required String accessToken,
  })  : _dio = dio,
        _accessToken = accessToken;

  final Dio _dio;
  final String _accessToken;

  static const String _baseUrl = 'https://api.mapbox.com/directions/v5';

  /// Calculate optimal route between origin and destination
  Future<DirectionsRoute> getOptimalRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
    bool alternatives = true,
    String language = 'en',
    bool steps = true,
    GeometryFormat geometryFormat = GeometryFormat.polyline,
  }) async {
    try {
      // Build coordinates string: origin;waypoints;destination
      final coordinates = _buildCoordinatesString(origin, destination, waypoints);
      
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/${profile.value}/$coordinates',
        queryParameters: {
          'access_token': _accessToken,
          'alternatives': alternatives,
          'geometries': geometryFormat.value,
          'language': language,
          'steps': steps,
          'banner_instructions': true,
          'voice_instructions': true,
          'annotations': 'duration,distance',
        },
      );

      if (response.data == null) {
        throw DirectionsException('Empty response from Mapbox Directions API');
      }

      final data = response.data!;
      
      // Check for API errors
      if (data['code'] != 'Ok') {
        final message = data['message'] ?? 'Unknown error';
        throw DirectionsException('Mapbox API error: $message');
      }

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw DirectionsException('No routes found');
      }

      // Return the first (optimal) route
      final routeData = routes.first as Map<String, dynamic>;
      return _parseDirectionsRoute(routeData);
      
    } on DioException catch (e) {
      print('❌ Mapbox API Error: ${e.response?.statusCode} - ${e.message}');
      if (e.response?.data != null) {
        print('❌ Error details: ${e.response!.data}');
      }
      
      // Log the request details for debugging 422 errors
      if (e.response?.statusCode == 422) {
        print('❌ Request URL: ${e.requestOptions.uri}');
        print('❌ Query parameters: ${e.requestOptions.queryParameters}');
      }
      
      if (e.response?.statusCode == 429) {
        throw DirectionsException('Rate limit exceeded. Please try again later.');
      } else if (e.response?.statusCode == 401) {
        throw DirectionsException('Invalid Mapbox access token.');
      } else if (e.response?.statusCode == 422) {
        final errorDetails = e.response?.data?.toString() ?? '';
        throw DirectionsException('Invalid coordinates or route parameters. Details: $errorDetails');
      } else if (e.type == DioExceptionType.connectionTimeout ||
                 e.type == DioExceptionType.receiveTimeout ||
                 e.type == DioExceptionType.connectionError) {
        throw DirectionsException('Network error. Please check your internet connection.');
      }
      
      throw DirectionsException('Failed to calculate route: ${e.message}');
    } catch (e) {
      if (e is DirectionsException) rethrow;
      throw DirectionsException('Unexpected error calculating route: $e');
    }
  }

  /// Get multiple route alternatives
  Future<List<DirectionsRoute>> getRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
    String language = 'en',
  }) async {
    try {
      final coordinates = _buildCoordinatesString(origin, destination, waypoints);
      
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/${profile.value}/$coordinates',
        queryParameters: {
          'access_token': _accessToken,
          'alternatives': true,
          'geometries': GeometryFormat.polyline.value,
          'language': language,
          'steps': true,
          'banner_instructions': true,
          'voice_instructions': true,
          'annotations': 'duration,distance',
        },
      );

      if (response.data == null) {
        throw DirectionsException('Empty response from Mapbox Directions API');
      }

      final data = response.data!;
      
      if (data['code'] != 'Ok') {
        final message = data['message'] ?? 'Unknown error';
        throw DirectionsException('Mapbox API error: $message');
      }

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw DirectionsException('No route alternatives found');
      }

      return routes
          .map((routeData) => _parseDirectionsRoute(routeData as Map<String, dynamic>))
          .toList();
      
    } on DioException catch (e) {
      print('❌ Mapbox API Error (alternatives): ${e.response?.statusCode} - ${e.message}');
      if (e.response?.data != null) {
        print('❌ Error details: ${e.response!.data}');
      }
      
      // Log the request details for debugging 422 errors
      if (e.response?.statusCode == 422) {
        print('❌ Request URL: ${e.requestOptions.uri}');
        print('❌ Query parameters: ${e.requestOptions.queryParameters}');
      }
      
      if (e.response?.statusCode == 429) {
        throw DirectionsException('Rate limit exceeded. Please try again later.');
      } else if (e.response?.statusCode == 401) {
        throw DirectionsException('Invalid Mapbox access token.');
      } else if (e.response?.statusCode == 422) {
        final errorDetails = e.response?.data?.toString() ?? '';
        throw DirectionsException('Invalid coordinates or route parameters. Details: $errorDetails');
      } else if (e.type == DioExceptionType.connectionTimeout ||
                 e.type == DioExceptionType.receiveTimeout ||
                 e.type == DioExceptionType.connectionError) {
        throw DirectionsException('Network error. Please check your internet connection.');
      }
      
      throw DirectionsException('Failed to get route alternatives: ${e.message}');
    } catch (e) {
      if (e is DirectionsException) rethrow;
      throw DirectionsException('Failed to get route alternatives: $e');
    }
  }

  /// Calculate route for a journey using its destination
  Future<DirectionsRoute> calculateJourneyRoute({
    required Journey journey,
    required geo.Position currentPosition,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  }) async {
    final origin = LatLng(
      latitude: currentPosition.latitude,
      longitude: currentPosition.longitude,
    );
    
    final destination = journey.destination;

    return getOptimalRoute(
      origin: origin,
      destination: destination,
      profile: profile,
    );
  }

  /// Get updated ETA for current position along route
  Future<Duration> getUpdatedETA({
    required DirectionsRoute route,
    required geo.Position currentPosition,
    required LatLng destination,
  }) async {
    try {
      // Calculate route from current position to destination
      final currentRoute = await getOptimalRoute(
        origin: LatLng(
          latitude: currentPosition.latitude,
          longitude: currentPosition.longitude,
        ),
        destination: destination,
        profile: DirectionsProfile.drivingTraffic,
        alternatives: false,
      );

      return currentRoute.totalDuration;
    } catch (e) {
      // Fallback to original route duration if recalculation fails
      return route.totalDuration;
    }
  }

  /// Build coordinates string for API request
  String _buildCoordinatesString(LatLng origin, LatLng destination, List<LatLng>? waypoints) {
    // Validate coordinates
    _validateCoordinates(origin, 'origin');
    _validateCoordinates(destination, 'destination');
    
    final coords = <String>[
      '${origin.longitude},${origin.latitude}',
    ];

    // Add waypoints if provided
    if (waypoints != null) {
      for (final waypoint in waypoints) {
        _validateCoordinates(waypoint, 'waypoint');
        coords.add('${waypoint.longitude},${waypoint.latitude}');
      }
    }

    // Add destination
    coords.add('${destination.longitude},${destination.latitude}');

    final coordinatesString = coords.join(';');
    print('🗺️ Mapbox coordinates string: $coordinatesString');
    return coordinatesString;
  }

  void _validateCoordinates(LatLng coords, String label) {
    if (coords.latitude < -90 || coords.latitude > 90) {
      throw DirectionsException('Invalid $label latitude: ${coords.latitude}. Must be between -90 and 90.');
    }
    if (coords.longitude < -180 || coords.longitude > 180) {
      throw DirectionsException('Invalid $label longitude: ${coords.longitude}. Must be between -180 and 180.');
    }
    print('✅ Valid $label coordinates: lat=${coords.latitude}, lng=${coords.longitude}');
  }

  /// Parse Mapbox Directions API response into DirectionsRoute
  DirectionsRoute _parseDirectionsRoute(Map<String, dynamic> routeData) {
    final geometry = routeData['geometry'] as String? ?? '';
    final duration = (routeData['duration'] as num?)?.toDouble() ?? 0.0;
    final distance = (routeData['distance'] as num?)?.toDouble() ?? 0.0;
    final weightName = routeData['weight_name'] as String?;
    final weight = (routeData['weight'] as num?)?.toDouble();

    // Parse legs
    final legsData = routeData['legs'] as List<dynamic>?;
    List<RouteLeg>? legs;
    if (legsData != null) {
      legs = legsData.map((legData) => _parseRouteLeg(legData as Map<String, dynamic>)).toList();
    }

    // Parse steps from all legs
    final steps = <NavigationStep>[];
    if (legs != null) {
      for (final leg in legs) {
        steps.addAll(leg.steps);
      }
    }

    return DirectionsRoute(
      geometry: geometry,
      duration: duration,
      distance: distance,
      steps: steps,
      legs: legs,
      weightName: weightName,
      weight: weight,
    );
  }

  /// Parse route leg from API response
  RouteLeg _parseRouteLeg(Map<String, dynamic> legData) {
    final duration = (legData['duration'] as num?)?.toDouble() ?? 0.0;
    final distance = (legData['distance'] as num?)?.toDouble() ?? 0.0;
    final summary = legData['summary'] as String?;

    final stepsData = legData['steps'] as List<dynamic>? ?? [];
    final steps = stepsData
        .map((stepData) => _parseNavigationStep(stepData as Map<String, dynamic>))
        .toList();

    return RouteLeg(
      duration: duration,
      distance: distance,
      steps: steps,
      summary: summary,
    );
  }

  /// Parse navigation step from API response
  NavigationStep _parseNavigationStep(Map<String, dynamic> stepData) {
    final distance = (stepData['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (stepData['duration'] as num?)?.toDouble() ?? 0.0;
    final geometry = stepData['geometry'] as String? ?? '';
    final instruction = stepData['maneuver']?['instruction'] as String? ?? '';
    final name = stepData['name'] as String?;
    final mode = stepData['mode'] as String?;
    final drivingSide = stepData['driving_side'] as String?;

    // Parse maneuver
    final maneuverData = stepData['maneuver'] as Map<String, dynamic>? ?? {};
    final maneuver = _parseStepManeuver(maneuverData);

    // Parse intersections
    final intersectionsData = stepData['intersections'] as List<dynamic>?;
    List<StepIntersection>? intersections;
    if (intersectionsData != null) {
      intersections = intersectionsData
          .map((data) => _parseStepIntersection(data as Map<String, dynamic>))
          .toList();
    }

    return NavigationStep(
      distance: distance,
      duration: duration,
      geometry: geometry,
      instruction: instruction,
      maneuver: maneuver,
      name: name,
      mode: mode,
      drivingSide: drivingSide,
      intersections: intersections,
    );
  }

  /// Parse step maneuver from API response
  StepManeuver _parseStepManeuver(Map<String, dynamic> maneuverData) {
    final type = maneuverData['type'] as String? ?? '';
    final instruction = maneuverData['instruction'] as String? ?? '';
    final bearingBefore = (maneuverData['bearing_before'] as num?)?.toDouble() ?? 0.0;
    final bearingAfter = (maneuverData['bearing_after'] as num?)?.toDouble() ?? 0.0;
    final location = (maneuverData['location'] as List<dynamic>?)
            ?.map((coord) => (coord as num).toDouble())
            .toList() ??
        [0.0, 0.0];
    final modifier = maneuverData['modifier'] as String?;

    return StepManeuver(
      type: type,
      instruction: instruction,
      bearingBefore: bearingBefore,
      bearingAfter: bearingAfter,
      location: location,
      modifier: modifier,
    );
  }

  /// Parse step intersection from API response
  StepIntersection _parseStepIntersection(Map<String, dynamic> intersectionData) {
    final location = (intersectionData['location'] as List<dynamic>?)
            ?.map((coord) => (coord as num).toDouble())
            .toList() ??
        [0.0, 0.0];
    final bearings = (intersectionData['bearings'] as List<dynamic>?)
            ?.map((bearing) => (bearing as num).toInt())
            .toList() ??
        [];
    final entry = (intersectionData['entry'] as List<dynamic>?)
            ?.map((e) => e as bool)
            .toList() ??
        [];
    final in_ = intersectionData['in'] as int?;
    final out = intersectionData['out'] as int?;

    return StepIntersection(
      location: location,
      bearings: bearings,
      entry: entry,
      in_: in_,
      out: out,
    );
  }
}

/// Exception thrown by MapboxDirectionsService
class DirectionsException implements Exception {
  const DirectionsException(this.message);
  final String message;

  @override
  String toString() => 'DirectionsException: $message';
}