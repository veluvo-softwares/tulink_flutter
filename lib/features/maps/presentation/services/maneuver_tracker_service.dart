import 'dart:math' as math;

import '../../data/models/route_result_model.dart';
import '../../domain/entities/maneuver.dart';

/// Tracks the user's progress through a route's turn-by-turn steps.
///
/// Uses **cumulative distance along the route polyline** to determine which
/// step the user is approaching and how far ahead the next maneuver is.
/// This is more reliable than the previous segment-index comparison because
/// it is independent of polyline coordinate density — a sparse polyline
/// (few coordinates per kilometre) and a dense one both produce the same
/// distance-based result.
///
/// ## Advancement rule
/// `_currentIndex` always points to the **next maneuver the user has not yet
/// executed**.  It advances when the user's cumulative distance along the
/// route equals or exceeds that maneuver's [Maneuver.cumulativeDistanceMetres].
///
/// ## distanceToNextManeuver
/// `= maneuver[_currentIndex].cumulativeDistanceMetres − distanceTravelled`
///
/// This counts down naturally as the user drives toward the turn, and resets
/// to the next step's lookahead distance as soon as the user passes a turn.
class ManeuverTrackerService {
  List<Maneuver> _maneuvers = const [];
  List<List<double>> _routeCoordinates = const [];

  /// Pre-computed cumulative distances: `_cumDist[i]` = total route distance
  /// (metres) from coordinate[0] to coordinate[i].
  List<double> _cumDist = const [];

  int _currentIndex = 0;

  List<Maneuver> get maneuvers => List.unmodifiable(_maneuvers);

  Maneuver? get currentManeuver =>
      _maneuvers.isEmpty ? null : _maneuvers[_currentIndex];

  int get currentIndex => _currentIndex;

  void loadRoute(RouteResultModel route) {
    _routeCoordinates = route.coordinates;
    _cumDist = _buildCumulativeDistances(route.coordinates);
    _maneuvers = _buildManeuvers(route);
    _currentIndex = 0;
    print(
      '🧭 ManeuverTracker: loaded ${_maneuvers.length} steps, '
      '${_routeCoordinates.length} coords, '
      'total ${_cumDist.isNotEmpty ? _cumDist.last.toStringAsFixed(0) : 0} m',
    );
  }

  void clear() {
    _maneuvers = const [];
    _routeCoordinates = const [];
    _cumDist = const [];
    _currentIndex = 0;
  }

  /// Update progress given the user's snapped position on the route.
  ///
  /// [segmentIndex] is the index of the route coordinate segment the user
  /// is currently on, as returned by [MapMatchingService].  The cumulative
  /// distance to that segment is looked up in [_cumDist] and used to:
  ///   1. Advance [_currentIndex] past any maneuvers the user has already
  ///      passed.
  ///   2. Compute [ManeuverProgress.distanceToNextManeuverMetres] as a simple
  ///      subtraction rather than a haversine call to an approximate anchor.
  ManeuverProgress update({
    required double snappedLatitude,
    required double snappedLongitude,
    required int segmentIndex,
  }) {
    if (_maneuvers.isEmpty || _cumDist.isEmpty) {
      return const ManeuverProgress(
        distanceToNextManeuverMetres: 0,
        distanceRemainingMetres: 0,
      );
    }

    // Distance the user has travelled along the route polyline. A segment
    // index alone identifies only the segment's *start*. On long/sparse
    // segments that made distance and ETA remain frozen until the next vertex
    // was crossed. Include the snapped point's progress within this segment.
    final safeSegmentIndex = segmentIndex.clamp(
      0,
      _routeCoordinates.length - 1,
    );
    final segmentStartDistance = _cumDist[safeSegmentIndex];
    final segmentEndDistance = safeSegmentIndex + 1 < _cumDist.length
        ? _cumDist[safeSegmentIndex + 1]
        : _cumDist.last;
    final segmentStart = _routeCoordinates[safeSegmentIndex];
    final distanceWithinSegment = _haversineMetres(
      segmentStart[1],
      segmentStart[0],
      snappedLatitude,
      snappedLongitude,
    );
    final distanceTravelled = (segmentStartDistance + distanceWithinSegment)
        .clamp(segmentStartDistance, segmentEndDistance);

    // Advance past any maneuvers whose position the user has already reached.
    while (_currentIndex < _maneuvers.length - 1 &&
        distanceTravelled >=
            _maneuvers[_currentIndex].cumulativeDistanceMetres) {
      _currentIndex++;
      print(
        '🧭 ManeuverTracker: step → $_currentIndex '
        '(${_maneuvers[_currentIndex].instruction})',
      );
    }

    // How far ahead the current (upcoming) maneuver is.
    final distanceToNext =
        (_maneuvers[_currentIndex].cumulativeDistanceMetres - distanceTravelled)
            .clamp(0.0, double.infinity);

    // Total remaining distance to the destination.
    final totalRoute = _cumDist.isNotEmpty ? _cumDist.last : 0.0;
    final remaining = (totalRoute - distanceTravelled).clamp(
      0.0,
      double.infinity,
    );

    return ManeuverProgress(
      distanceToNextManeuverMetres: distanceToNext,
      distanceRemainingMetres: remaining,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Pre-compute cumulative distances along the polyline so each [update]
  /// call is O(1) rather than O(n).
  static List<double> _buildCumulativeDistances(List<List<double>> coords) {
    if (coords.isEmpty) return const [];
    final d = List<double>.filled(coords.length, 0.0);
    for (int i = 1; i < coords.length; i++) {
      d[i] =
          d[i - 1] +
          _haversineMetres(
            coords[i - 1][1],
            coords[i - 1][0],
            coords[i][1],
            coords[i][0],
          );
    }
    return d;
  }

  /// Build [Maneuver] list from the backend route response.
  ///
  /// Each maneuver's [Maneuver.cumulativeDistanceMetres] is the cumulative
  /// route distance **at the point where that maneuver is executed** (i.e.
  /// the sum of all previous steps' distances).  The [update] method advances
  /// [_currentIndex] when the user's travelled distance reaches this value.
  static List<Maneuver> _buildManeuvers(RouteResultModel route) {
    final result = <Maneuver>[];
    double cumulative = 0;

    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];

      // Approximate anchor coordinate by the proportional position along the
      // polyline — used only for display purposes in the convoy overlay, not
      // for advancement logic.
      final fraction = route.distanceMetres > 0
          ? (cumulative / route.distanceMetres).clamp(0.0, 1.0)
          : 0.0;
      final coordIndex = (fraction * (route.coordinates.length - 1))
          .round()
          .clamp(0, route.coordinates.length - 1);

      result.add(
        Maneuver(
          index: i,
          instruction: step.instruction,
          maneuverType: step.maneuver,
          distanceMetres: step.distanceMetres,
          cumulativeDistanceMetres: cumulative,
          coordinate: route.coordinates[coordIndex],
        ),
      );

      cumulative += step.distanceMetres;
    }

    return result;
  }

  static double _haversineMetres(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class ManeuverProgress {
  final double distanceToNextManeuverMetres;
  final double distanceRemainingMetres;

  const ManeuverProgress({
    required this.distanceToNextManeuverMetres,
    required this.distanceRemainingMetres,
  });
}
