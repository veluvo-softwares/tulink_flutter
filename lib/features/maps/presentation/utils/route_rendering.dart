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
}) {
  if (routeCoordinates.length < 2) return const <List<double>>[];

  final safeSegmentIndex = segmentIndex.clamp(0, routeCoordinates.length - 2);

  return <List<double>>[
    <double>[snappedLongitude, snappedLatitude],
    ...routeCoordinates.sublist(safeSegmentIndex + 1),
  ];
}
