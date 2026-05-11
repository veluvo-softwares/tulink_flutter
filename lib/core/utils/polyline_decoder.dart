import 'dart:math' as math;
import '../../../features/journeys/domain/entities/journey.dart';

/// Utility class for decoding Google Polyline encoded strings
/// Used to convert Mapbox route geometry into coordinate lists
class PolylineDecoder {
  /// Decode a polyline string into a list of coordinates
  /// Supports both polyline (precision 5) and polyline6 (precision 6) formats
  static List<LatLng> decode(String encoded, {int precision = 6}) {
    if (encoded.isEmpty) return [];

    final coordinates = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    try {
      while (index < encoded.length) {
        // Decode latitude
        int shift = 0;
        int result = 0;
        int byte;
        
        do {
          byte = encoded.codeUnitAt(index++) - 63;
          result |= (byte & 0x1F) << shift;
          shift += 5;
        } while (byte >= 0x20);
        
        final deltaLat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
        lat += deltaLat;

        // Decode longitude
        shift = 0;
        result = 0;
        
        do {
          byte = encoded.codeUnitAt(index++) - 63;
          result |= (byte & 0x1F) << shift;
          shift += 5;
        } while (byte >= 0x20);
        
        final deltaLng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
        lng += deltaLng;

        // Convert to degrees based on precision
        final factor = _precisionFactor(precision);
        coordinates.add(LatLng(
          latitude: lat / factor,
          longitude: lng / factor,
        ));
      }
    } catch (e) {
      print('❌ Error decoding polyline: $e');
      return [];
    }

    return coordinates;
  }

  /// Encode a list of coordinates into a polyline string
  static String encode(List<LatLng> coordinates, {int precision = 6}) {
    if (coordinates.isEmpty) return '';

    final factor = _precisionFactor(precision);
    final encoded = StringBuffer();
    
    int prevLat = 0;
    int prevLng = 0;

    try {
      for (final coord in coordinates) {
        final lat = (coord.latitude * factor).round();
        final lng = (coord.longitude * factor).round();

        final deltaLat = lat - prevLat;
        final deltaLng = lng - prevLng;

        encoded.write(_encodeSignedNumber(deltaLat));
        encoded.write(_encodeSignedNumber(deltaLng));

        prevLat = lat;
        prevLng = lng;
      }
    } catch (e) {
      print('❌ Error encoding polyline: $e');
      return '';
    }

    return encoded.toString();
  }

  /// Get the precision factor for the given precision level
  static double _precisionFactor(int precision) {
    switch (precision) {
      case 5:
        return 1e5; // Standard Google Polyline precision
      case 6:
        return 1e6; // Mapbox Polyline6 precision
      default:
        return 1e6; // Default to precision 6
    }
  }

  /// Encode a signed number for polyline algorithm
  static String _encodeSignedNumber(int num) {
    int sgnNum = num << 1;
    if (num < 0) {
      sgnNum = ~sgnNum;
    }
    return _encodeNumber(sgnNum);
  }

  /// Encode a number for polyline algorithm
  static String _encodeNumber(int num) {
    final encoded = StringBuffer();
    
    while (num >= 0x20) {
      final nextValue = (0x20 | (num & 0x1F)) + 63;
      encoded.writeCharCode(nextValue);
      num >>= 5;
    }
    
    final finalValue = num + 63;
    encoded.writeCharCode(finalValue);
    
    return encoded.toString();
  }

  /// Calculate the total distance of a polyline in meters
  static double calculatePolylineDistance(List<LatLng> coordinates) {
    if (coordinates.length < 2) return 0.0;

    double totalDistance = 0.0;
    
    for (int i = 0; i < coordinates.length - 1; i++) {
      final from = coordinates[i];
      final to = coordinates[i + 1];
      totalDistance += _haversineDistance(from, to);
    }

    return totalDistance;
  }

  /// Calculate distance between two coordinates using Haversine formula
  static double _haversineDistance(LatLng from, LatLng to) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final dLat = _degreesToRadians(to.latitude - from.latitude);
    final dLng = _degreesToRadians(to.longitude - from.longitude);
    
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_degreesToRadians(from.latitude)) *
            _cos(_degreesToRadians(to.latitude)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);
    
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (3.14159265359 / 180.0);
  }

  // Math utility functions using dart:math
  static double _sin(double x) => math.sin(x);
  static double _cos(double x) => math.cos(x);
  static double _sqrt(double x) => math.sqrt(x);
  static double _atan2(double y, double x) => math.atan2(y, x);
}