import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/usecases/stream_convoy_positions.dart';
import '../../domain/usecases/publish_my_position.dart';
import '../../domain/usecases/fetch_latest_snapshot.dart';
import '../../domain/repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/services/location_permission_service.dart';

/// Provider for convoy coordination state management
/// Handles real-time position sharing and convoy member tracking
class ConvoyProvider extends ChangeNotifier {
  ConvoyProvider({
    required StreamConvoyPositions streamConvoyPositions,
    required PublishMyPosition publishMyPosition,
    required FetchLatestSnapshot fetchLatestSnapshot,
    required ConvoyRepository repository,
  })  : _streamConvoyPositions = streamConvoyPositions,
        _publishMyPosition = publishMyPosition,
        _fetchLatestSnapshot = fetchLatestSnapshot,
        _repository = repository;

  final StreamConvoyPositions _streamConvoyPositions;
  final PublishMyPosition _publishMyPosition;
  final FetchLatestSnapshot _fetchLatestSnapshot;
  final ConvoyRepository _repository;

  // State
  ConvoySnapshot? _snapshot;
  bool _isPublishing = false;
  bool _isSubscribed = false;
  ConvoyConnectionState _connectionState = ConvoyConnectionState.disconnected;
  String? _errorMessage;

  // GPS and location publishing
  StreamSubscription<Position>? _locationSubscription;
  DateTime? _lastPublishTime;
  DateTime? _lastMovementTime;
  bool _isInHeartbeatMode = false;
  Timer? _heartbeatTimer;

  // Convoy stream subscriptions
  StreamSubscription<({ConvoySnapshot? snapshot, Failure? failure})>? _convoySubscription;
  StreamSubscription<ConvoyConnectionState>? _connectionSubscription;

  // Dependencies
  final Battery _battery = Battery();

  // Getters
  ConvoySnapshot? get snapshot => _snapshot;
  bool get isPublishing => _isPublishing;
  bool get isSubscribed => _isSubscribed;
  ConvoyConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;

  /// Start convoy coordination for a journey
  /// Begins both GPS publishing and real-time position streaming
  Future<void> startCoordination(String journeyId) async {
    try {
      _clearError();
      
      // Check permissions first
      final permissionResult = await LocationPermissionService.requestLocationPermission();
      if (!permissionResult.granted) {
        _setError(permissionResult.failure?.message ?? 'Location permissions required for convoy coordination');
        throw permissionResult.failure ?? ConvoyFailure.locationPermissionDenied;
      }

      // Start location publishing
      await _startLocationPublishing(journeyId);
      
      // Start convoy position streaming
      _startConvoyStream(journeyId);
      
      _isSubscribed = true;
      notifyListeners();
      
    } catch (e) {
      print('❌ Failed to start convoy coordination: $e');
      final failure = e is Failure ? e : ConvoyFailure(
        message: 'Failed to start convoy coordination',
        details: 'An unexpected error occurred: $e',
        timestamp: DateTime.now(),
      );
      _setError(failure.message);
    }
  }

  /// Stop convoy coordination
  /// Cancels GPS publishing and real-time streaming
  Future<void> stopCoordination() async {
    print('🛑 ConvoyProvider: Stopping coordination...');
    
    // Stop location publishing
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _isPublishing = false;
    
    // Stop heartbeat timer
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isInHeartbeatMode = false;
    
    // Stop convoy streaming
    await _convoySubscription?.cancel();
    _convoySubscription = null;
    
    // Stop connection state monitoring
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    // Stop the repository coordination (WebSocket, etc.)
    try {
      await _repository.stopCoordination();
      print('✅ ConvoyProvider: Repository coordination stopped');
    } catch (e) {
      print('⚠️ ConvoyProvider: Failed to stop repository coordination: $e');
    }
    
    _isSubscribed = false;
    
    // Reset state
    _snapshot = null;
    _connectionState = ConvoyConnectionState.disconnected;
    _lastPublishTime = null;
    _lastMovementTime = null;
    _clearError();
    
    print('✅ ConvoyProvider: Coordination stopped completely');
    notifyListeners();
  }


  /// Start GPS location publishing with throttling
  Future<void> _startLocationPublishing(String journeyId) async {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Emit on 5m movement
    );

    try {
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) => _handleLocationUpdate(journeyId, position),
        onError: (error) {
          print('❌ Location stream error: $error');
          _setError('GPS error: $error');
        },
      );

      _isPublishing = true;
      notifyListeners();
      
    } catch (e) {
      print('❌ Failed to start location stream: $e');
      throw ConvoyFailure.locationServiceDisabled;
    }
  }

  /// Handle new GPS location with throttling and heartbeat logic
  Future<void> _handleLocationUpdate(String journeyId, Position position) async {
    final now = DateTime.now();
    final speed = position.speed ?? 0.0;
    final isMoving = speed > 0.5; // Moving if speed > 0.5 m/s

    // Update movement tracking
    if (isMoving) {
      _lastMovementTime = now;
      if (_isInHeartbeatMode) {
        _exitHeartbeatMode(); // Exit heartbeat mode when movement detected
      }
    }

    // Check if we should throttle the update
    if (_shouldThrottleUpdate(now, isMoving)) {
      return;
    }

    // Enter heartbeat mode if stationary for 15+ seconds
    if (!isMoving && !_isInHeartbeatMode && _lastMovementTime != null) {
      final timeSinceMovement = now.difference(_lastMovementTime!);
      if (timeSinceMovement.inSeconds >= 15) {
        _enterHeartbeatMode(journeyId);
        return;
      }
    }

    await _publishLocation(journeyId, position, isMoving);
  }

  /// Check if update should be throttled (max 1 per second)
  bool _shouldThrottleUpdate(DateTime now, bool isMoving) {
    if (_lastPublishTime == null) return false;
    
    final timeSinceLastPublish = now.difference(_lastPublishTime!);
    return timeSinceLastPublish.inMilliseconds < 1000; // Max 1 per second
  }

  /// Enter heartbeat mode (stationary for 15+ seconds)
  void _enterHeartbeatMode(String journeyId) {
    if (_isInHeartbeatMode) return;
    
    _isInHeartbeatMode = true;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      Geolocator.getCurrentPosition().then((position) {
        _publishLocation(journeyId, position, false);
      }).catchError((error) {
        print('⚠️ Heartbeat location update failed: $error');
      });
    });
  }

  /// Exit heartbeat mode when movement is detected
  void _exitHeartbeatMode() {
    if (!_isInHeartbeatMode) return;
    
    _isInHeartbeatMode = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Publish location to backend
  Future<void> _publishLocation(String journeyId, Position position, bool isMoving) async {
    try {
      // Get battery level
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (e) {
        // Battery info not available, continue without it
      }

      final result = await _publishMyPosition(
        journeyId: journeyId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
        accuracy: position.accuracy,
        altitude: position.altitude,
        heading: position.heading,
        speed: position.speed,
        batteryLevel: batteryLevel,
        isMoving: isMoving,
      );

      if (result.success) {
        _lastPublishTime = DateTime.now();
      } else {
        print('⚠️ Failed to publish location: ${result.failure?.message}');
        // Don't show error to user for failed publishes - just log and continue
      }
      
    } catch (e) {
      print('⚠️ Location publish error: $e');
      // Don't show error to user for failed publishes - just log and continue
    }
  }

  /// Start streaming convoy positions and connection state
  void _startConvoyStream(String journeyId) {
    // Listen to convoy position updates
    _convoySubscription = _streamConvoyPositions(journeyId).listen(
      (result) {
        if (result.snapshot != null) {
          _snapshot = result.snapshot;
          _clearError();
        } else if (result.failure != null) {
          _setError(result.failure!.message);
        }
        notifyListeners();
      },
      onError: (error) {
        print('❌ Convoy stream error: $error');
        final failure = error is Failure ? error : ConvoyFailure.rtdbConnectionFailed;
        _setError(failure.message);
        notifyListeners();
      },
    );

    // Listen to WebSocket connection state changes
    _connectionSubscription = _repository.connectionStateStream.listen(
      (connectionState) {
        _connectionState = connectionState;
        notifyListeners();
      },
      onError: (error) {
        print('❌ Connection state error: $error');
        _connectionState = ConvoyConnectionState.error;
        notifyListeners();
      },
    );
  }

  /// Fetch latest snapshot manually (for refresh)
  Future<void> refreshSnapshot(String journeyId) async {
    try {
      final result = await _fetchLatestSnapshot(journeyId);
      if (result.snapshot != null) {
        _snapshot = result.snapshot;
        _clearError();
      } else if (result.failure != null) {
        _setError(result.failure!.message);
      }
      notifyListeners();
    } catch (e) {
      print('❌ Failed to refresh snapshot: $e');
      _setError('Failed to refresh convoy data');
    }
  }

  /// Get convoy snapshot for display (excludes current user from markers)
  ConvoySnapshot? getDisplaySnapshot(String currentUserId) {
    if (_snapshot == null) return null;
    
    // Always filter out current user for marker display to avoid duplicate with built-in user location
    // The Mapbox built-in location component handles showing the user's own position
    return _snapshot!.filterOutUser(currentUserId);
  }

  /// Get convoy snapshot for member counting (includes current user)  
  ConvoySnapshot? getFullSnapshot() {
    return _snapshot;
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error manually
  void clearError() {
    _clearError();
  }

  /// Set snapshot for testing purposes only
  @visibleForTesting
  void setSnapshotForTesting(ConvoySnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    stopCoordination();
    super.dispose();
  }
}