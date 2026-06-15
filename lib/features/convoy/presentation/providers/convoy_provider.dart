import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
import '../../domain/entities/participant_arrived_event.dart';
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
  Position? _lastKnownPosition;

  /// Fixed-cadence beacon timer. Convoy members must keep publishing their
  /// position even while stationary, otherwise they disappear from everyone
  /// else's map. GPS movement events alone are insufficient because a still
  /// device emits nothing.
  Timer? _publishTimer;
  static const Duration _publishInterval = Duration(seconds: 4);

  // Convoy stream subscriptions
  StreamSubscription<({ConvoySnapshot? snapshot, Failure? failure})>? _convoySubscription;
  StreamSubscription<ConvoyConnectionState>? _connectionSubscription;
  StreamSubscription<JourneyEndedEvent>? _journeyEndedSubscription;
  StreamSubscription<ParticipantArrivedEvent>? _participantArrivedSubscription;
  StreamSubscription<String>? _journeyStartedSubscription;
  StreamSubscription<String>? _participantAcceptedSubscription;

  /// User-scoped invite subscription. Lives for the whole session (set up by
  /// [startUserChannel]); deliberately NOT torn down by [stopCoordination],
  /// which is journey-scoped.
  StreamSubscription<Map<String, dynamic>>? _journeyInviteSubscription;

  /// Last journey-ended event received. Surfaced to the UI so screens can
  /// react (toast, navigate away) and clear after handling.
  JourneyEndedEvent? _lastJourneyEndedEvent;
  JourneyEndedEvent? get lastJourneyEndedEvent => _lastJourneyEndedEvent;

  /// Set when the backend emits `journey-started`. Home screen watches this
  /// to auto-navigate members to the map. Cleared by [consumeJourneyStartedEvent].
  String? _pendingJourneyStartedId;
  String? get pendingJourneyStartedId => _pendingJourneyStartedId;

  /// Rolling arrival progress. Updated by the server's `participant-arrived`
  /// events. `_totalMemberCount` here comes from the server payload (the
  /// authoritative count of journey participants) rather than the snapshot's
  /// `members` map, which only contains people whose positions we've seen.
  int _arrivedCount = 0;
  int _totalMemberCount = 0;
  ParticipantArrivedEvent? _lastArrivalEvent;

  int get arrivedCount => _arrivedCount;
  int get totalMemberCount => _totalMemberCount;
  ParticipantArrivedEvent? get lastArrivalEvent => _lastArrivalEvent;

  /// Increments every time an invited member accepts (server `participant-accepted`
  /// event) for the journey we're currently in. Screens showing the participant
  /// list watch this and re-fetch the journey so the leader sees the accepted
  /// state live, without a manual reload.
  int _participantAcceptedTick = 0;
  int get participantAcceptedTick => _participantAcceptedTick;

  /// Increments every time the backend pushes a `journey-invite` to this user
  /// over the WebSocket user channel. The home screen watches this to refresh
  /// the invite list and show a banner without a reload. [lastJourneyInvite]
  /// holds the payload of the most recent invite (journeyName, etc.).
  int _journeyInviteTick = 0;
  int get journeyInviteTick => _journeyInviteTick;
  Map<String, dynamic>? _lastJourneyInvite;
  Map<String, dynamic>? get lastJourneyInvite => _lastJourneyInvite;

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
    // Already fully coordinating (subscribed + publishing GPS) — nothing to do.
    if (_currentJourneyId == journeyId && _isSubscribed && _isPublishing) {
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

      // Start location publishing (GPS)
      await _startLocationPublishing(journeyId);

      // Set up convoy streams only if not already subscribed (e.g. joinJourneyRoom
      // was called first and streams are already running in listener mode).
      if (!_isSubscribed) {
        _startConvoyStream(journeyId);
      }

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

  /// Open the user-scoped WebSocket channel so the user receives `journey-invite`
  /// pushes live (e.g. while sitting on the home screen). Connects the socket
  /// and keeps it alive across convoy start/stop. Idempotent — call once after
  /// login. FCM covers the case where the app is backgrounded/closed.
  Future<void> startUserChannel() async {
    try {
      await _repository.connectUserChannel();

      _journeyInviteSubscription ??= _repository.journeyInviteStream.listen(
        (invite) {
          print('📨 ConvoyProvider: journey-invite $invite');
          _lastJourneyInvite = invite;
          _journeyInviteTick++;
          notifyListeners();
        },
        onError: (Object error) {
          print('❌ journey-invite stream error: $error');
        },
      );
    } catch (e) {
      print('❌ Failed to start user channel: $e');
    }
  }

  /// Close the user-scoped channel (call on logout). Cancels the invite
  /// subscription and drops the socket if no journey is using it.
  Future<void> stopUserChannel() async {
    await _journeyInviteSubscription?.cancel();
    _journeyInviteSubscription = null;
    await _repository.disconnectUserChannel();
  }

  /// Join a journey room to receive real-time events without starting GPS.
  /// Used by members waiting on the home screen for the leader to start.
  Future<void> joinJourneyRoom(String journeyId) async {
    if (_currentJourneyId == journeyId && _isSubscribed) return;

    try {
      _clearError();
      _currentJourneyId = journeyId;

      _startConvoyStream(journeyId);

      _isSubscribed = true;
      notifyListeners();
      print('✅ ConvoyProvider: joined journey room $journeyId (listener mode)');
    } catch (e) {
      print('❌ ConvoyProvider: failed to join room: $e');
      _currentJourneyId = null;
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
    
    // Stop the fixed-cadence beacon timer
    _publishTimer?.cancel();
    _publishTimer = null;
    
    // Stop convoy streaming
    await _convoySubscription?.cancel();
    _convoySubscription = null;
    
    // Stop connection state monitoring
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    // Stop journey-ended monitoring
    await _journeyEndedSubscription?.cancel();
    _journeyEndedSubscription = null;

    // Stop participant-arrived monitoring
    await _participantArrivedSubscription?.cancel();
    _participantArrivedSubscription = null;

    // Stop journey-started monitoring
    await _journeyStartedSubscription?.cancel();
    _journeyStartedSubscription = null;
    _pendingJourneyStartedId = null;

    // Stop participant-accepted monitoring
    await _participantAcceptedSubscription?.cancel();
    _participantAcceptedSubscription = null;
    
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
    _lastKnownPosition = null;
    _currentJourneyId = null;
    _consecutivePublishFailures = 0;
    _arrivedCount = 0;
    _totalMemberCount = 0;
    _lastArrivalEvent = null;
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
      // Seed an initial position immediately so we beacon before the first
      // movement event arrives (a still device emits nothing on its own).
      try {
        final initial = await Geolocator.getCurrentPosition();
        _lastKnownPosition = initial;
        await _publishLocation(journeyId, initial, false);
      } catch (e) {
        print('⚠️ Failed to get initial position: $e');
      }

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) => _handleLocationUpdate(journeyId, position),
        onError: (error) {
          print('❌ Location stream error: $error');
          _setError('GPS error: $error');
        },
      );

      // Fixed-cadence beacon: republish the last known position on a steady
      // interval even while stationary, so parked / just-joined members stay
      // visible to the rest of the convoy.
      _publishTimer?.cancel();
      _publishTimer = Timer.periodic(_publishInterval, (_) {
        final position = _lastKnownPosition;
        if (position == null) return;
        _publishLocation(journeyId, position, (position.speed ?? 0.0) > 0.5);
      });

      _isPublishing = true;
      notifyListeners();
      
    } catch (e) {
      print('❌ Failed to start location stream: $e');
      throw ConvoyFailure.locationServiceDisabled;
    }
  }

  /// Handle a new GPS location from the movement stream. Caches the position
  /// for the periodic beacon and publishes immediately (throttled to 1/sec)
  /// for responsive live tracking while moving.
  Future<void> _handleLocationUpdate(String journeyId, Position position) async {
    _lastKnownPosition = position;

    final now = DateTime.now();
    final isMoving = (position.speed ?? 0.0) > 0.5; // Moving if speed > 0.5 m/s

    // Throttle movement-driven publishes to max 1/sec; the periodic beacon
    // guarantees a baseline cadence regardless of movement.
    if (_shouldThrottleUpdate(now, isMoving)) {
      return;
    }

    await _publishLocation(journeyId, position, isMoving);
  }

  /// Check if update should be throttled (max 1 per second)
  bool _shouldThrottleUpdate(DateTime now, bool isMoving) {
    if (_lastPublishTime == null) return false;
    
    final timeSinceLastPublish = now.difference(_lastPublishTime!);
    return timeSinceLastPublish.inMilliseconds < 1000; // Max 1 per second
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

    if (_isSilentTerminalFailure(failure)) {
      print('🤫 Silent terminal failure — stopping coordination without UI surface');
      await stopCoordination();
      return;
    }

    if (_isTerminalPublishFailure(failure)) {
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

  /// Terminal failures the backend signals as "stop, this is expected" —
  /// no toast, no error banner, just stop the publish loop and clear state.
  bool _isSilentTerminalFailure(Failure failure) {
    return failure is ConvoyFailure && failure == ConvoyFailure.stopPolling;
  }

  /// Whether a failure means the journey/auth is gone for good and we should
  /// stop the publish loop entirely (vs. a transient network blip).
  bool _isTerminalPublishFailure(Failure failure) {
    if (failure is ConvoyFailure) {
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


    // Per-participant arrival updates. On allArrived we stop publishing GPS
    // immediately — the backend auto-completes the journey and the
    // journey-ended subscription above handles the navigation/teardown.
    _participantArrivedSubscription = _repository.participantArrivedStream.listen(
      (event) async {
        _arrivedCount = event.arrivedCount;
        _totalMemberCount = event.totalCount;
        _lastArrivalEvent = event;

        if (event.allArrived) {
          print('🏁 ConvoyProvider: all participants arrived — stopping publishing');
          await _stopLocationPublishing();
        }

        notifyListeners();
      },
      onError: (Object error) {
        print('❌ participant-arrived stream error: $error');
      },
    );

    _journeyStartedSubscription = _repository.journeyStartedStream.listen(
      (journeyId) {
        if (journeyId == _currentJourneyId) {
          print('🚀 ConvoyProvider: journey-started for $journeyId');
          _pendingJourneyStartedId = journeyId;
          notifyListeners();
        }
      },
      onError: (Object error) {
        print('❌ journey-started stream error: $error');
      },
    );

    _participantAcceptedSubscription =
        _repository.participantAcceptedStream.listen(
      (journeyId) {
        if (journeyId == _currentJourneyId) {
          print('🤝 ConvoyProvider: participant-accepted for $journeyId');
          _participantAcceptedTick++;
          notifyListeners();
        }
      },
      onError: (Object error) {
        print('❌ participant-accepted stream error: $error');
      },
    );
  }

  /// Stops just the GPS publishing side (location stream + heartbeat) while
  /// leaving snapshot/connection subscriptions intact. Used when the backend
  /// signals allArrived: we want to silence the publish loop but stay in the
  /// room long enough to receive the journey-ended event that follows.
  Future<void> _stopLocationPublishing() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _isPublishing = false;

    _publishTimer?.cancel();
    _publishTimer = null;
  }

  /// Consume the last arrival event after the UI has reacted (toast,
  /// notification). Prevents the same event from being acted on twice.
  void consumeArrivalEvent() {
    _lastArrivalEvent = null;
    notifyListeners();
  }

  /// Consume the last journey-ended event. The UI calls this after it has
  /// reacted (shown a toast, navigated) so the same event isn't acted on twice.
  void consumeJourneyEndedEvent() {
    _lastJourneyEndedEvent = null;
    notifyListeners();
  }

  /// Consume the pending journey-started event after the UI has navigated.
  void consumeJourneyStartedEvent() {
    _pendingJourneyStartedId = null;
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
    
    // Mapbox built-in location component shows the user's own position,
    // so we exclude them from the convoy markers to avoid a duplicate dot.
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
