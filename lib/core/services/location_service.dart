import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Bounded, injectable access to device location.
///
/// Every call site in the app must go through this abstraction rather than
/// calling [Geolocator.getCurrentPosition] directly. A raw `getCurrentPosition`
/// future never completes when the device cannot produce a fix (simulator with
/// no location, cold GPS indoors), and because it neither completes nor throws,
/// a surrounding `try/catch` cannot recover from it. Awaiting one on a
/// lifecycle-critical path deadlocks that path permanently — which is exactly
/// how the live journey screen and convoy start used to wedge.
///
/// Implementations must therefore guarantee that [getCurrentPosition] always
/// settles within [defaultTimeout], returning `null` instead of hanging or
/// throwing for the ordinary "no fix available" case.
abstract class LocationService {
  /// Upper bound applied to a single fix attempt when no explicit timeout is
  /// supplied. Chosen to match the existing 5 s bounds already used by the map
  /// screen's camera-follow calls.
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// Best-effort current position.
  ///
  /// Returns `null` — never hangs, never throws — when no fix can be obtained
  /// within [timeout]. Implementations should fall back to the last known
  /// position before giving up so a warm cache still yields a usable value.
  Future<Position?> getCurrentPosition({Duration? timeout});

  /// Last position the platform cached, or `null`. Never throws.
  Future<Position?> getLastKnownPosition();

  /// Continuous position stream used for live tracking.
  Stream<Position> getPositionStream({LocationSettings? locationSettings});
}

/// [LocationService] backed by the `geolocator` plugin.
class GeolocatorLocationService implements LocationService {
  /// Creates the production location service.
  const GeolocatorLocationService();

  @override
  Future<Position?> getCurrentPosition({Duration? timeout}) async {
    final limit = timeout ?? LocationService.defaultTimeout;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(limit);
    } catch (_) {
      // Timeout, permission loss, or platform error — fall back to whatever
      // the platform already has rather than failing the caller outright.
      return getLastKnownPosition();
    }
  }

  @override
  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
