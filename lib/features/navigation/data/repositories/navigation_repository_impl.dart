import 'package:geolocator/geolocator.dart' as geo;
import '../services/mapbox_directions_service.dart';
import '../../domain/repositories/navigation_repository.dart';
import '../../domain/entities/directions_route.dart';
import '../../../journeys/domain/entities/journey.dart';
import '../../../../core/common/result.dart';
import '../../../../core/errors/failure.dart';

/// Implementation of NavigationRepository using Mapbox Directions API
class NavigationRepositoryImpl implements NavigationRepository {
  NavigationRepositoryImpl(this._directionsService);

  final MapboxDirectionsService _directionsService;

  @override
  Future<Result<DirectionsRoute>> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  }) async {
    try {
      final route = await _directionsService.getOptimalRoute(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
        profile: profile,
      );

      return (data: route, failure: null);
    } on DirectionsException catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: e.message,
          timestamp: DateTime.now(),
        ));
    } catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: 'Failed to calculate route',
          details: e.toString(),
          timestamp: DateTime.now(),
        ));
    }
  }

  @override
  Future<Result<List<DirectionsRoute>>> getRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  }) async {
    try {
      final routes = await _directionsService.getRouteAlternatives(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
        profile: profile,
      );

      return (data: routes, failure: null);
    } on DirectionsException catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: e.message,
          timestamp: DateTime.now(),
        ));
    } catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: 'Failed to get route alternatives',
          details: e.toString(),
          timestamp: DateTime.now(),
        ));
    }
  }

  @override
  Future<Result<DirectionsRoute>> calculateJourneyRoute({
    required Journey journey,
    required geo.Position currentPosition,
    DirectionsProfile profile = DirectionsProfile.drivingTraffic,
  }) async {
    try {
      final route = await _directionsService.calculateJourneyRoute(
        journey: journey,
        currentPosition: currentPosition,
        profile: profile,
      );

      return (data: route, failure: null);
    } on DirectionsException catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: e.message,
          timestamp: DateTime.now(),
        ));
    } catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: 'Failed to calculate journey route',
          details: e.toString(),
          timestamp: DateTime.now(),
        ));
    }
  }

  @override
  Future<Result<Duration>> getUpdatedETA({
    required DirectionsRoute route,
    required geo.Position currentPosition,
    required LatLng destination,
  }) async {
    try {
      final eta = await _directionsService.getUpdatedETA(
        route: route,
        currentPosition: currentPosition,
        destination: destination,
      );

      return (data: eta, failure: null);
    } on DirectionsException catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: e.message,
          timestamp: DateTime.now(),
        ));
    } catch (e) {
      return (data: null, failure:
        NavigationFailure(
          message: 'Failed to get updated ETA',
          details: e.toString(),
          timestamp: DateTime.now(),
        ));
    }
  }
}

/// Navigation-specific failure class
class NavigationFailure extends Failure {
  const NavigationFailure({
    required super.message,
    super.details,
    super.timestamp,
  });

  static const NavigationFailure routeCalculationFailed = NavigationFailure(
    message: 'Failed to calculate route',
    details: 'Unable to find a valid route to destination',
  );

  static const NavigationFailure invalidCoordinates = NavigationFailure(
    message: 'Invalid coordinates provided',
    details: 'Origin or destination coordinates are not valid',
  );

  static const NavigationFailure noRouteFound = NavigationFailure(
    message: 'No route found',
    details: 'Unable to find any route between origin and destination',
  );

  static const NavigationFailure apiLimitExceeded = NavigationFailure(
    message: 'API rate limit exceeded',
    details: 'Too many requests to the directions API. Please try again later.',
  );

  static const NavigationFailure networkError = NavigationFailure(
    message: 'Network error',
    details: 'Unable to connect to directions service. Check internet connection.',
  );

  @override
  NavigationFailure copyWith({
    String? message,
    int? statusCode,
    String? details,
    DateTime? timestamp,
  }) {
    return NavigationFailure(
      message: message ?? this.message,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}