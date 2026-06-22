import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:geocoding/geocoding.dart';

/// Resolves the user's ISO 3166-1 alpha-2 region code for search biasing.
///
/// Order of preference: physical location (reverse-geocode) → device locale →
/// null (let the backend default). The result is cached in-memory so it is not
/// re-derived on every keystroke, but the cache is keyed to the location it was
/// resolved at and is refreshed once the device moves far enough that the
/// country may have changed (e.g. a cross-border road trip) — see
/// [_recacheDistanceKm].
///
/// Privacy: logs only the resolution source, never coordinates.
class RegionService {
  RegionService._();

  static String? _cached;
  static double? _cachedLat;
  static double? _cachedLng;

  /// Distance (km) the device must move from the last resolution point before
  /// the cached region is re-derived. Large enough that per-keystroke searches
  /// at one place always hit the cache, small enough to catch a country change.
  static const double _recacheDistanceKm = 25;

  /// Returns a 2-letter uppercase region code, or null if it can't be
  /// determined (in which case the caller should omit the param and let the
  /// backend default).
  ///
  /// Pass the same [lat]/[lng] already acquired for location bias — no second
  /// location request is made here.
  static Future<String?> resolveRegionCode({double? lat, double? lng}) async {
    if (_cached != null && !_movedSignificantly(lat, lng)) {
      return _cached;
    }

    // 1. Physical location → reverse-geocoded country (most accurate).
    if (lat != null && lng != null) {
      try {
        final placemarks = await placemarkFromCoordinates(lat, lng);
        final code = placemarks.isEmpty
            ? null
            : normalizeRegionCode(placemarks.first.isoCountryCode);
        if (code != null) {
          print('✅ region: location');
          return _store(code, lat, lng);
        }
      } catch (_) {
        // Reverse geocoding unavailable — fall through to locale.
      }
    }

    // 2. Device locale's region setting (zero-cost, not physical location).
    final localeCode = normalizeRegionCode(
      ui.PlatformDispatcher.instance.locale.countryCode,
    );
    if (localeCode != null) {
      print('✅ region: locale');
      return _store(localeCode, lat, lng);
    }

    // 3. Unresolved — let the backend default.
    print('⚠️ region: none');
    return null;
  }

  /// Normalises a raw country code to a validated 2-letter uppercase code,
  /// or null when it doesn't match `^[A-Z]{2}$` after trimming/upcasing.
  static String? normalizeRegionCode(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ? normalized : null;
  }

  /// Test/seam hook to clear the cache.
  static void reset() {
    _cached = null;
    _cachedLat = null;
    _cachedLng = null;
  }

  static String _store(String code, double? lat, double? lng) {
    _cached = code;
    _cachedLat = lat;
    _cachedLng = lng;
    return code;
  }

  /// True when [lat]/[lng] are far enough from the last resolution point that
  /// the cached region should be re-derived. Unknown coords never invalidate.
  static bool _movedSignificantly(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (_cachedLat == null || _cachedLng == null) return true;
    return _distanceKm(_cachedLat!, _cachedLng!, lat, lng) > _recacheDistanceKm;
  }

  /// Great-circle distance in kilometres between two coordinates (haversine).
  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }
}
