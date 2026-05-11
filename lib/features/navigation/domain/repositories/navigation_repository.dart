import 'package:geolocator/geolocator.dart' as geo;
import '../../../journeys/domain/entities/journey.dart';
import '../entities/directions_route.dart';
import '../../../../core/common/result.dart';

/// Repository interface for navigation-related operations
abstract class NavigationRepository {
  /// Calculate optimal route for a journey
  Future<Result<DirectionsRoute>> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  });

  /// Get route alternatives
  Future<Result<List<DirectionsRoute>>> getRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  });

  /// Calculate route for a specific journey
  Future<Result<DirectionsRoute>> calculateJourneyRoute({
    required Journey journey,
    required geo.Position currentPosition,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  });

  /// Get updated ETA for current position along route
  Future<Result<Duration>> getUpdatedETA({
    required DirectionsRoute route,
    required geo.Position currentPosition,
    required LatLng destination,
  });
}