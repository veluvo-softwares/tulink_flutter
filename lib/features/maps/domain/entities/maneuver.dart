import 'package:equatable/equatable.dart';

/// A single turn-by-turn maneuver step along a route.
///
/// Wraps the raw `RouteStepModel` from the backend with a stable, domain-level
/// representation enriched with the step's cumulative distance from route
/// origin and its anchor coordinate. Consumed by [ManeuverTrackerService] to
/// determine which step the user is currently approaching.
class Maneuver extends Equatable {
  /// Zero-based index of this step within the route's step list.
  final int index;

  /// Plain-language instruction sourced from the Mapbox Directions API
  /// via the backend, e.g. "Turn right onto Waiyaki Way."
  final String instruction;

  /// Maneuver type token from Mapbox: 'depart', 'turn', 'roundabout',
  /// 'rotary', 'fork', 'merge', 'end of road', 'arrive', etc.
  final String maneuverType;

  /// Length of this step in metres (distance until the next maneuver).
  final double distanceMetres;

  /// Cumulative distance from route origin to the start of this step.
  /// Used for progress calculation along the route.
  final double cumulativeDistanceMetres;

  /// Coordinate where this maneuver occurs, in [longitude, latitude]
  /// order (GeoJSON convention to match Mapbox).
  final List<double> coordinate;

  const Maneuver({
    required this.index,
    required this.instruction,
    required this.maneuverType,
    required this.distanceMetres,
    required this.cumulativeDistanceMetres,
    required this.coordinate,
  });

  /// Latitude of the maneuver anchor.
  double get latitude => coordinate[1];

  /// Longitude of the maneuver anchor.
  double get longitude => coordinate[0];

  @override
  List<Object?> get props => [
        index,
        instruction,
        maneuverType,
        distanceMetres,
        cumulativeDistanceMetres,
        coordinate,
      ];
}
