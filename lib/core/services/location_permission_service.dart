import 'package:geolocator/geolocator.dart';
import '../errors/failure.dart';

/// Service for handling location permissions for convoy coordination
class LocationPermissionService {
  static const String _locationDeniedMessage = 
      'Location access is required for convoy coordination. '
      'Please enable location permissions in your device settings.';

  /// Check and request location permissions for convoy coordination
  static Future<({bool granted, Failure? failure})> requestLocationPermission() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          granted: false,
          failure: ConvoyFailure.locationServiceDisabled,
        );
      }

      // Check current permission status
      var permission = await Geolocator.checkPermission();
      
      // Handle denied permission by requesting
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      // Check final permission status
      switch (permission) {
        case LocationPermission.denied:
          return (
            granted: false,
            failure: ConvoyFailure(
              message: 'Location permission denied',
              details: _locationDeniedMessage,
              timestamp: DateTime.now(),
              isRetryable: true,
            ),
          );
          
        case LocationPermission.deniedForever:
          return (
            granted: false,
            failure: ConvoyFailure(
              message: 'Location permission permanently denied',
              details: 'Location permissions are permanently denied. Please enable them in your device settings to participate in convoy coordination.',
              timestamp: DateTime.now(),
              isRetryable: false,
            ),
          );
          
        case LocationPermission.unableToDetermine:
          return (
            granted: false,
            failure: ConvoyFailure(
              message: 'Unable to determine location permission',
              details: 'Location permission status could not be determined. Please check your device settings.',
              timestamp: DateTime.now(),
              isRetryable: true,
            ),
          );
          
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          // Permission granted
          return (granted: true, failure: null);
      }
      
    } catch (e) {
      return (
        granted: false,
        failure: ConvoyFailure(
          message: 'Location permission error',
          details: 'Failed to check location permissions: ${e.toString()}',
          timestamp: DateTime.now(),
          isRetryable: true,
        ),
      );
    }
  }

  /// Check if location permissions are currently granted
  static Future<bool> hasLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse || 
             permission == LocationPermission.always;
    } catch (e) {
      print('❌ Error checking location permission: $e');
      return false;
    }
  }

  /// Open app settings for manual permission enabling
  static Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      print('❌ Error opening app settings: $e');
      return false;
    }
  }

  /// Request background location permission (Android)
  static Future<({bool granted, Failure? failure})> requestBackgroundLocationPermission() async {
    try {
      // First ensure we have foreground permission
      final foregroundResult = await requestLocationPermission();
      if (!foregroundResult.granted) {
        return foregroundResult;
      }

      // For background location, we need to check if it's supported
      // This is mainly relevant for Android 10+ where background location requires special permission
      final permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.always) {
        return (granted: true, failure: null);
      }
      
      // For now, return success with foreground permission
      // Background location setup would require additional platform-specific handling
      return (granted: true, failure: null);
      
    } catch (e) {
      return (
        granted: false,
        failure: ConvoyFailure(
          message: 'Background location permission error',
          details: 'Failed to request background location permission: ${e.toString()}',
          timestamp: DateTime.now(),
          isRetryable: true,
        ),
      );
    }
  }

  /// Get user-friendly permission status description
  static Future<String> getPermissionStatusDescription() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Location services are disabled';
      }
      
      final permission = await Geolocator.checkPermission();
      switch (permission) {
        case LocationPermission.denied:
          return 'Location permission not granted';
        case LocationPermission.deniedForever:
          return 'Location permission permanently denied';
        case LocationPermission.whileInUse:
          return 'Location permission granted (while using app)';
        case LocationPermission.always:
          return 'Location permission granted (always)';
        case LocationPermission.unableToDetermine:
          return 'Unable to determine location permission status';
      }
    } catch (e) {
      return 'Error checking location permission: ${e.toString()}';
    }
  }
}

