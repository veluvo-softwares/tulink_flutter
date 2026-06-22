import 'dart:math' as math;

import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';

/// Estimates a convoy peer's *display* position between broadcast updates.
///
/// Mapbox does not tween between discrete GeoJSON source updates, so peer
/// markers snap from one received fix to the next. This service projects the
/// last known [MemberPosition] forward along its reported `heading` at its
/// reported `speed` for the time elapsed since the fix, producing a smooth
/// glide between updates.
///
/// It works for peers because it only needs broadcast data (lat, lng, speed,
/// heading, timestamp) — never their device sensors.
///
/// All math is pure — no I/O, no listeners — mirroring `MapMatchingService`,
/// so it is safe to call on every render tick and fully unit-testable.
///
/// The projection is **display-only**: callers must never write the result
/// back into the snapshot, the provider, or anything that publishes. The
/// authoritative position is always the last received [MemberPosition].
class ConvoyInterpolationService {
  /// Maximum time (seconds) to extrapolate past the last fix. Beyond this the
  /// last known position is held, so a dropped peer's marker never runs away
  /// off-screen — it simply waits where it was last seen.
  static const double maxExtrapolationSeconds = 6;

  /// Below this speed (m/s, ≈1.8 km/h) the heading is unreliable and there is
  /// no meaningful movement to interpolate, so the raw position is returned.
  static const double minSpeedMps = 0.5;

  static const double _earthRadiusMetres = 6371000;

  /// Project [position] forward to [nowMillis] and return the estimated
  /// display coordinate as `[longitude, latitude]`.
  ///
  /// Returns the raw position unchanged when speed is below [minSpeedMps],
  /// when `heading` is null, or when no time has elapsed since the fix. The
  /// elapsed time is clamped to [maxExtrapolationSeconds].
  static List<double> interpolatedPosition(
    MemberPosition position,
    int nowMillis,
  ) {
    final speed = position.speed;
    final heading = position.heading;

    if (speed == null || speed < minSpeedMps || heading == null) {
      return <double>[position.longitude, position.latitude];
    }

    final elapsedSeconds = ((nowMillis - position.timestamp) / 1000.0).clamp(
      0.0,
      maxExtrapolationSeconds,
    );
    if (elapsedSeconds <= 0.0) {
      return <double>[position.longitude, position.latitude];
    }

    final distanceMetres = speed * elapsedSeconds;

    return _projectForward(
      latitude: position.latitude,
      longitude: position.longitude,
      headingDegrees: heading,
      distanceMetres: distanceMetres,
    );
  }

  /// Forward geodesic (destination-point) projection: from a start point,
  /// travel [distanceMetres] along a compass [headingDegrees] bearing (0 =
  /// north, clockwise). Returns `[longitude, latitude]`.
  static List<double> _projectForward({
    required double latitude,
    required double longitude,
    required double headingDegrees,
    required double distanceMetres,
  }) {
    final angularDistance = distanceMetres / _earthRadiusMetres;
    final bearing = headingDegrees * math.pi / 180.0;
    final lat1 = latitude * math.pi / 180.0;
    final lng1 = longitude * math.pi / 180.0;

    final sinLat2 =
        math.sin(lat1) * math.cos(angularDistance) +
        math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing);
    final lat2 = math.asin(sinLat2);

    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * sinLat2,
        );

    return <double>[lng2 * 180.0 / math.pi, lat2 * 180.0 / math.pi];
  }
}
