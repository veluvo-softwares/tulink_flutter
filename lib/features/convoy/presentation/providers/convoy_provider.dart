import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
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

  /// The journey we're currently coordinating for, or null if stopped.
  /// Used to prevent dual-journey leaks: starting a new journey without
  /// first stopping the previous one was causing GPS publishes for journey A
  /// while the WebSocket was still subscribed to journey B.
  String? _currentJourneyId;

  /// Tracks consecutive publish failures — used to bail out on a backend
  /// that's permanently refusing publishes (journey ended, auth dead, etc.)
  /// rather than spinning forever.
  int _consecutivePublishFailures = 0;
  static const int _maxConsecutivePublishFailures = 5;

  // GPS and location publishing
  StreamSubscription<Position>? _locationSubscription;
  DateTime? _lastPublishTime;
  DateTime? _lastMovementTime;
  bool _isInHeartbeatMode = false;
  Timer? _heartbeatTimer;

  // Convoy stream subscriptions
  StreamSubscription<({ConvoySnapshot? snapshot, Failure? failure})>? _convoySubscription;
  StreamSubscription<ConvoyConnectionState>? _connectionSubscription;
  StreamSubscription<JourneyEndedEvent>? _journeyEndedSubscription;

  /// Last journey-ended event received. Surfaced to the UI so screens can
  /// react (toast, navigate away) and clear after handling.
  JourneyEndedEvent? _lastJourneyEndedEvent;
  JourneyEndedEvent? get lastJourneyEndedEvent => _lastJourneyEndedEvent;

  // Dependencies
  final Battery _battery = Battery();

  // Getters
  ConvoySnapshot? get snapshot => _snapshot;
  bool get isPublishing => _isPublishing;
  bool get isSubscribed => _isSubscribed;
  ConvoyConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  String? get currentJourneyId => _currentJourneyId;

  /// Start convoy coordination for a journey.
  /// Begins both GPS publishing and real-time position streaming.
  ///
  /// Idempotent: if we're already coordinating the same journey, this is a
  /// no-op. If we're coordinating a *different* journey, that one is stopped
  /// first to avoid leaking subscriptions / GPS streams across journeys.
  Future<void> startCoordination(String journeyId) async {
    // Already coordinating this journey — nothing to do.
    if (_currentJourneyId == journeyId && _isSubscribed) {
      return;
    }

    // Switching journeys — tear down the previous one cleanly.
    if (_currentJourneyId != null && _currentJourneyId != journeyId) {
      print(
        '🔀 ConvoyProvider: switching from $_currentJourneyId to $journeyId, '
        'stopping previous coordination first',
      );
      await stopCoordination();
    }

    try {
      _clearError();
      _currentJourneyId = journeyId;

      // Check permissions first
      final permissionResult = await LocationPermissionService.requestLocationPermission();
      if (!permissionResult.granted) {
        _setError(permissionResult.failure?.message ?? 'Location permissions required for convoy coordination');
        _currentJourneyId = null;
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
      _currentJourneyId = null;
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

    // Stop journey-ended monitoring
    await _journeyEndedSubscription?.cancel();
    _journeyEndedSubscription = null;
    
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
    _currentJourneyId = null;
    _consecutivePublishFailures = 0;
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

  /// Publish location to backend.
  ///
  /// Bails out (calls [stopCoordination]) on terminal failures:
  ///  - Journey is no longer active (backend rejects publish)
  ///  - Auth is dead (user is no longer authorized for this journey)
  ///  - Too many consecutive failures (circuit breaker)
  ///
  /// Transient failures (network, rate limit) are logged and retried on the
  /// next GPS tick.
  Future<void> _publishLocation(String journeyId, Position position, bool isMoving) async {
    // Guard against stale callbacks after stopCoordination.
    if (_currentJourneyId != journeyId) return;

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
        _consecutivePublishFailures = 0;
        return;
      }

      // We got a structured failure — decide whether to bail or keep trying.
      await _handlePublishFailure(result.failure);
    } catch (e) {
      // Unexpected (shouldn't happen — repository normalizes errors), but
      // count it so a sustained crash loop still trips the circuit breaker.
      print('⚠️ Location publish error: $e');
      await _handlePublishFailure(
        e is Failure
            ? e
            : ConvoyFailure(
                message: 'Location publish failed',
                details: e.toString(),
                timestamp: DateTime.now(),
              ),
      );
    }
  }

  /// Decide whether a publish failure is terminal (stop) or transient (retry).
  Future<void> _handlePublishFailure(Failure? failure) async {
    if (failure == null) return;

    final isTerminal = _isTerminalPublishFailure(failure);
    if (isTerminal) {
      print('🛑 Terminal publish failure (${failure.message}) — stopping coordination');
      _setError(failure.message);
      await stopCoordination();
      return;
    }

    _consecutivePublishFailures++;
    print(
      '⚠️ Transient publish failure ($_consecutivePublishFailures/$_maxConsecutivePublishFailures): '
      '${failure.message}',
    );

    if (_consecutivePublishFailures >= _maxConsecutivePublishFailures) {
      print('🛑 Publish failure circuit breaker tripped — stopping coordination');
      _setError('Connection lost. Tap to reconnect.');
      await stopCoordination();
    }
  }

  /// Whether a failure means the journey/auth is gone for good and we should
  /// stop the publish loop entirely (vs. a transient network blip).
  bool _isTerminalPublishFailure(Failure failure) {
    if (failure is ConvoyFailure) {
      // journeyNotActive: backend says the journey is ended/cancelled.
      // notJourneyMember: 401/403 — auth is dead or we've been kicked out.
      return failure == ConvoyFailure.journeyNotActive ||
          failure == ConvoyFailure.notJourneyMember ||
          failure.message.toLowerCase().contains('not active') ||
          failure.message.toLowerCase().contains('not authorized') ||
          failure.message.toLowerCase().contains('not a member');
    }
    if (failure is AuthFailure || failure is TokenFailure) {
      return true;
    }
    if (failure is ServerFailure) {
      final code = failure.statusCode ?? 0;
      return code == 401 || code == 403;
    }
    return false;
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

    // Listen for server-driven journey-ended events. When the backend ends
    // a journey it emits this; we must stop coordinating that journey so we
    // don't keep hammering the now-invalid room.
    _journeyEndedSubscription = _repository.journeyEndedStream.listen(
      (event) async {
        // Ignore stale events from a previous journey.
        if (event.journeyId != _currentJourneyId) return;

        print('🏁 ConvoyProvider: journey-ended received for ${event.journeyId}');
        _lastJourneyEndedEvent = event;
        _setError('Journey ended');
        await stopCoordination();
        notifyListeners();
      },
      onError: (error) {
        print('❌ journey-ended stream error: $error');
      },
    );
  }

  /// Consume the last journey-ended event. The UI calls this after it has
  /// reacted (shown a toast, navigated) so the same event isn't acted on twice.
  void consumeJourneyEndedEvent() {
    _lastJourneyEndedEvent = null;
    notifyListeners();
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