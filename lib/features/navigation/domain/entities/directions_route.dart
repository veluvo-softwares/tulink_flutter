import 'package:equatable/equatable.dart';
import '../../data/models/navigation_step.dart';

/// Represents a calculated route from Mapbox Directions API
class DirectionsRoute extends Equatable {
  const DirectionsRoute({
    required this.geometry,
    required this.duration,
    required this.distance,
    required this.steps,
    this.legs,
    this.weightName,
    this.weight,
  });

  /// Route geometry as encoded polyline
  final String geometry;

  /// Total route duration in seconds
  final double duration;

  /// Total route distance in meters
  final double distance;

  /// List of turn-by-turn navigation steps
  final List<NavigationStep> steps;

  /// Route legs (segments between waypoints)
  final List<RouteLeg>? legs;

  /// Weight name used for route calculation
  final String? weightName;

  /// Total route weight
  final double? weight;

  /// Get total duration as Duration object
  Duration get totalDuration => Duration(seconds: duration.round());

  /// Get formatted distance string
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.round()} m';
    }
    final km = distance / 1000;
    return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
  }

  /// Get formatted duration string
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    
    if (hours == 0) {
      return '${minutes}min';
    }
    return '${hours}h ${minutes}min';
  }

  /// Get estimated arrival time from now
  DateTime get estimatedArrival {
    return DateTime.now().add(totalDuration);
  }

  /// Get formatted estimated arrival time
  String get formattedArrivalTime {
    final arrival = estimatedArrival;
    final hour = arrival.hour.toString().padLeft(2, '0');
    final minute = arrival.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  List<Object?> get props => [
        geometry,
        duration,
        distance,
        steps,
        legs,
        weightName,
        weight,
      ];
}

/// Represents a leg of the route (segment between waypoints)
class RouteLeg extends Equatable {
  const RouteLeg({
    required this.distance,
    required this.duration,
    required this.steps,
    this.summary,
  });

  final double distance;
  final double duration;
  final List<NavigationStep> steps;
  final String? summary;

  @override
  List<Object?> get props => [distance, duration, steps, summary];
}

/// Route profile options for Mapbox Directions API
enum DirectionsProfile {
  driving('mapbox/driving'),
  drivingTraffic('mapbox/driving-traffic'),
  walking('mapbox/walking'),
  cycling('mapbox/cycling');

  const DirectionsProfile(this.value);
  final String value;
}

/// Route geometry format options
enum GeometryFormat {
  geojson('geojson'),
  polyline('polyline'),
  polyline6('polyline6');

  const GeometryFormat(this.value);
  final String value;
}