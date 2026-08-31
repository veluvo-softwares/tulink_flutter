import 'dart:math' as math;

/// Builds the visible, untravelled portion of a navigation route.
///
/// [segmentIndex] identifies the segment containing the snapped position. The
/// returned line begins at that exact snapped position, then continues from
/// the next route vertex. Starting at the original segment vertex leaves a
/// visible gap between a moving puck and the route on sparse polylines.
List<List<double>> buildRemainingRouteCoordinates({
  required List<List<double>> routeCoordinates,
  required int segmentIndex,
  required double snappedLongitude,
  required double snappedLatitude,
  bool isOffRoute = false,
}) {
  if (routeCoordinates.length < 2) return const <List<double>>[];

  // An off-route snap is the device's raw GPS position. Prepending it to a
  // road polyline draws an invented straight connector from the device to a
  // later route vertex — the long diagonal seen in Android field testing.
  // Keep the real road geometry intact until rerouting produces a new route.
  if (isOffRoute) {
    return routeCoordinates
        .map((coordinate) => List<double>.from(coordinate))
        .toList(growable: false);
  }

  final safeSegmentIndex = segmentIndex.clamp(0, routeCoordinates.length - 2);

  return <List<double>>[
    <double>[snappedLongitude, snappedLatitude],
    ...routeCoordinates.sublist(safeSegmentIndex + 1),
  ];
}

/// Moves a rendered puck along the route geometry between two snapped fixes.
///
/// A direct latitude/longitude tween cuts across the inside of a turn. This
/// function walks the intervening route vertices instead and reports the
/// segment containing the interpolated point, allowing the puck and trimmed
/// polyline to advance through a corner as one unit.
({double longitude, double latitude, int segmentIndex})
interpolateRoutePosition({
  required List<List<double>> routeCoordinates,
  required double startLongitude,
  required double startLatitude,
  required int startSegmentIndex,
  required double targetLongitude,
  required double targetLatitude,
  required int targetSegmentIndex,
  required double t,
}) {
  if (routeCoordinates.length < 2) {
    return (
      longitude: targetLongitude,
      latitude: targetLatitude,
      segmentIndex: targetSegmentIndex,
    );
  }

  final lastSegment = routeCoordinates.length - 2;
  final startSegment = startSegmentIndex.clamp(0, lastSegment);
  final targetSegment = targetSegmentIndex.clamp(0, lastSegment);
  final progress = t.clamp(0.0, 1.0);

  // A backwards map-match correction is normally GPS jitter. Do not walk the
  // long way through the route; ease directly to the corrected snapped point.
  if (targetSegment < startSegment) {
    return (
      longitude: startLongitude + (targetLongitude - startLongitude) * progress,
      latitude: startLatitude + (targetLatitude - startLatitude) * progress,
      segmentIndex: progress < 1 ? startSegment : targetSegment,
    );
  }

  final path = <List<double>>[
    <double>[startLongitude, startLatitude],
    for (var vertex = startSegment + 1; vertex <= targetSegment; vertex++)
      routeCoordinates[vertex],
    <double>[targetLongitude, targetLatitude],
  ];

  final lengths = <double>[];
  var totalLength = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    final length = _coordinateDistance(path[i], path[i + 1]);
    lengths.add(length);
    totalLength += length;
  }

  if (totalLength == 0 || progress >= 1) {
    return (
      longitude: targetLongitude,
      latitude: targetLatitude,
      segmentIndex: targetSegment,
    );
  }

  var remaining = totalLength * progress;
  for (var i = 0; i < lengths.length; i++) {
    final length = lengths[i];
    if (remaining <= length || i == lengths.length - 1) {
      final localT = length == 0 ? 1.0 : (remaining / length).clamp(0.0, 1.0);
      return (
        longitude: path[i][0] + (path[i + 1][0] - path[i][0]) * localT,
        latitude: path[i][1] + (path[i + 1][1] - path[i][1]) * localT,
        segmentIndex: (startSegment + i).clamp(0, targetSegment),
      );
    }
    remaining -= length;
  }

  return (
    longitude: targetLongitude,
    latitude: targetLatitude,
    segmentIndex: targetSegment,
  );
}

double _coordinateDistance(List<double> a, List<double> b) {
  final meanLatitude = (a[1] + b[1]) * 0.5 * math.pi / 180.0;
  final dx = (b[0] - a[0]) * math.cos(meanLatitude);
  final dy = b[1] - a[1];
  return math.sqrt(dx * dx + dy * dy);
}
