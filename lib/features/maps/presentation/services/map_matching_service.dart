import 'dart:math' as math;

/// Snaps raw GPS coordinates to the closest point on a route polyline.
///
/// GPS readings on mobile devices jitter by 5–20 metres in urban canyons
/// and can briefly place the user on the wrong side of a divided road.
/// This service projects the raw coordinate onto the nearest line segment
/// of the route and returns the projected point.
///
/// All math is pure — no I/O, no listeners. Safe to call on every GPS tick.
class MapMatchingService {
  /// Maximum deviation (in metres) at which a GPS reading is still
  /// considered on-route. Beyond this the raw coordinate is returned
  /// unmodified and the caller should treat the user as potentially
  /// off-route.
  static const double maxSnapDistanceMetres = 30.0;

  /// Snap a raw GPS coordinate to the closest point on the route.
  ///
  /// When [currentSegmentIndex] is provided the search window is restricted to
  /// `[currentSegmentIndex - 2, route.length - 1]`.  The 2-segment lookback
  /// tolerates GPS jitter without allowing already-passed segments to
  /// artificially zero-out the deviation reading.  Without the window the
  /// user could drive an entirely different road that runs parallel to an
  /// earlier part of the original route and the detector would see near-zero
  /// deviation, resetting its off-route streak on every such frame.
  static SnapResult snap({
    required double rawLatitude,
    required double rawLongitude,
    required List<List<double>> route,
    int? currentSegmentIndex,
  }) {
    if (route.length < 2) {
      return SnapResult(
        snappedLatitude: rawLatitude,
        snappedLongitude: rawLongitude,
        deviationMetres: 0,
        isOnRoute: true,
        segmentIndex: 0,
      );
    }

    double minDistance = double.infinity;
    double bestLat = rawLatitude;
    double bestLng = rawLongitude;
    int bestSegmentIndex = 0;

    // Clamp the look-ahead start to avoid negative indices.
    final startIndex = currentSegmentIndex != null && currentSegmentIndex >= 2
        ? currentSegmentIndex - 2
        : 0;

    for (int i = startIndex; i < route.length - 1; i++) {
      final segStart = route[i];
      final segEnd = route[i + 1];

      final projected = _projectOntoSegment(
        pointLat: rawLatitude,
        pointLng: rawLongitude,
        segStartLat: segStart[1],
        segStartLng: segStart[0],
        segEndLat: segEnd[1],
        segEndLng: segEnd[0],
      );

      final distance = _haversineMetres(
        rawLatitude,
        rawLongitude,
        projected[0],
        projected[1],
      );

      if (distance < minDistance) {
        minDistance = distance;
        bestLat = projected[0];
        bestLng = projected[1];
        bestSegmentIndex = i;
      }
    }

    final isOnRoute = minDistance <= maxSnapDistanceMetres;

    return SnapResult(
      snappedLatitude: isOnRoute ? bestLat : rawLatitude,
      snappedLongitude: isOnRoute ? bestLng : rawLongitude,
      deviationMetres: minDistance,
      isOnRoute: isOnRoute,
      segmentIndex: bestSegmentIndex,
    );
  }

  /// Projects a geographic point onto a line segment using equirectangular
  /// approximation. Accurate enough for sub-kilometre distances at any
  /// non-polar latitude. Returns [latitude, longitude].
  static List<double> _projectOntoSegment({
    required double pointLat,
    required double pointLng,
    required double segStartLat,
    required double segStartLng,
    required double segEndLat,
    required double segEndLng,
  }) {
    final cosLat = math.cos(segStartLat * math.pi / 180.0);
    final dx = (segEndLng - segStartLng) * cosLat;
    final dy = segEndLat - segStartLat;
    final px = (pointLng - segStartLng) * cosLat;
    final py = pointLat - segStartLat;

    final segLengthSq = dx * dx + dy * dy;
    if (segLengthSq == 0) {
      return [segStartLat, segStartLng];
    }

    final t = ((px * dx + py * dy) / segLengthSq).clamp(0.0, 1.0);

    return [
      segStartLat + t * dy,
      segStartLng + (t * dx / cosLat),
    ];
  }

  /// Great-circle distance in metres between two geographic points.
  static double _haversineMetres(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMetres = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMetres * c;
  }
}

/// Result of snapping a raw GPS coordinate to a route polyline.
class SnapResult {
  final double snappedLatitude;
  final double snappedLongitude;
  final double deviationMetres;
  final bool isOnRoute;
  final int segmentIndex;

  const SnapResult({
    required this.snappedLatitude,
    required this.snappedLongitude,
    required this.deviationMetres,
    required this.isOnRoute,
    required this.segmentIndex,
  });
}
