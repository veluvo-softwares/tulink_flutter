import 'package:equatable/equatable.dart';

import 'maneuver.dart';

/// Snapshot of the user's progress along the active route at a moment in time.
///
/// Emitted by [NavigationProvider] on every GPS tick during an active journey.
/// Consumed by `TurnInstructionCard` and optionally by `JourneyProgressCard`
/// when it wants real road-distance values rather than its hardcoded 25.0 km
/// solo fallback.
class RouteProgress extends Equatable {
  /// The maneuver the user is currently approaching.
  final Maneuver currentManeuver;

  /// Distance in metres from the user's snapped position to the start of
  /// the next maneuver. Drives the "In 200 m" countdown shown in the HUD.
  final double distanceToNextManeuverMetres;

  /// Total distance remaining to the destination in metres.
  final double distanceRemainingMetres;

  /// Estimated time remaining to the destination in seconds. Computed from
  /// the original route duration scaled by remaining distance.
  final double durationRemainingSeconds;

  /// User's GPS-snapped position on the route (lat, lng). When off-route
  /// detection fires, this falls back to the raw GPS coordinate.
  final double snappedLatitude;
  final double snappedLongitude;

  /// True when the user has drifted far enough from the route to trigger
  /// a reroute request. Informational for the UI — the reroute itself is
  /// dispatched by [OffRouteDetectionService].
  final bool isOffRoute;

  /// Index of the route coordinate segment the user is currently on.
  /// Used by the map screen to trim the drawn polyline so only the
  /// remaining portion of the route is visible ahead of the driver.
  final int currentSegmentIndex;

  const RouteProgress({
    required this.currentManeuver,
    required this.distanceToNextManeuverMetres,
    required this.distanceRemainingMetres,
    required this.durationRemainingSeconds,
    required this.snappedLatitude,
    required this.snappedLongitude,
    required this.isOffRoute,
    this.currentSegmentIndex = 0,
  });

  @override
  List<Object?> get props => [
        currentManeuver,
        distanceToNextManeuverMetres,
        distanceRemainingMetres,
        durationRemainingSeconds,
        snappedLatitude,
        snappedLongitude,
        isOffRoute,
        currentSegmentIndex,
      ];
}
