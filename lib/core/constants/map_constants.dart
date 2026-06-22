/// A simple immutable geographic coordinate (degrees), used for shared map
/// constants that must not depend on any mapping SDK type.
class MapCoordinate {
  const MapCoordinate({required this.latitude, required this.longitude});

  /// Geographic latitude in degrees.
  final double latitude;

  /// Geographic longitude in degrees.
  final double longitude;
}

/// Default map centre (Nairobi). Used as the last-resort location-bias point
/// for place search when neither a live nor a last-known device position is
/// available, so a destination search is never sent fully unbiased.
const MapCoordinate kDefaultMapCenter = MapCoordinate(
  latitude: -1.2921,
  longitude: 36.8219,
);
