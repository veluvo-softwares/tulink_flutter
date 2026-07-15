import 'dart:async';

import '../datasources/convoy_remote_data_source.dart';
import '../datasources/convoy_websocket_data_source.dart';
import '../models/location_update_dto.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
import '../../domain/entities/participant_arrived_event.dart';
import '../../domain/repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/auth/token_manager.dart';

/// Implementation of convoy repository
/// Coordinates between WebSocket (real-time) and REST API (publishing/fallback)
/// This follows the backend-mediated architecture where:
/// - Location publishing: Mobile → Backend API (REST)
/// - Real-time updates: Backend → WebSocket → Mobile
/// - Fallback: REST polling when WebSocket disconnected
class ConvoyRepositoryImpl implements ConvoyRepository {
  ConvoyRepositoryImpl({
    required ConvoyRemoteDataSource remoteDataSource,
    required ConvoyWebSocketDataSource webSocketDataSource,
    required TokenManager tokenManager,
  }) : _remoteDataSource = remoteDataSource,
       _webSocketDataSource = webSocketDataSource,
       _tokenManager = tokenManager;

  final ConvoyRemoteDataSource _remoteDataSource;
  final ConvoyWebSocketDataSource _webSocketDataSource;
  final TokenManager _tokenManager;

  StreamSubscription<ConvoySnapshot>? _webSocketSubscription;
  final StreamController<({ConvoySnapshot? snapshot, Failure? failure})>
  _snapshotController = StreamController.broadcast();

  Timer? _fallbackPollingTimer;
  bool _isWebSocketConnected = false;
  String? _currentJourneyId;
  // When true, the socket is kept alive across convoy stop so the user keeps
  // receiving user-scoped events (journey invites) on the home screen.
  bool _userChannelActive = false;
  // Prevents the fallback polling timer from restarting after a terminal
  // failure (e.g. journey ended, user kicked out). Reset only in stopCoordination().
  bool _terminalFailureDetected = false;

  @override
  Stream<({ConvoySnapshot? snapshot, Failure? failure})> streamConvoyPositions(
    String journeyId,
  ) {
    _currentJourneyId = journeyId;

    // Start both WebSocket connection and initial REST fetch
    _startCoordination(journeyId);

    return _snapshotController.stream;
  }

  /// Start convoy coordination with WebSocket + REST fallback
  Future<void> _startCoordination(String journeyId) async {
    try {
      // Verify we have valid authentication before starting
      final token = await _tokenManager.getValidAuthToken();
      if (token == null) {
        print('❌ Cannot start convoy coordination - no valid auth token');
        final failure = ConvoyFailure(
          message: 'Authentication required',
          details: 'Please log in to join convoy coordination',
          timestamp: DateTime.now(),
          isRetryable: true,
        );
        _snapshotController.add((snapshot: null, failure: failure));
        return;
      }

      // First: Get immediate snapshot via REST (cold start)
      _fetchInitialSnapshot(journeyId);

      // Second: Connect WebSocket for real-time updates
      await _connectWebSocket();

      // Third: Join journey room for live updates
      await _webSocketDataSource.joinJourney(journeyId);
    } catch (e) {
      print('❌ Failed to start convoy coordination: $e');
      final failure = e is Failure
          ? e
          : ConvoyFailure(
              message: 'Failed to start convoy coordination',
              details: 'Could not connect to live updates: $e',
              timestamp: DateTime.now(),
              isRetryable: true,
            );
      _snapshotController.add((snapshot: null, failure: failure));

      // Fall back to REST polling
      _startRestFallbackPolling(journeyId);
    }
  }

  /// Connect to WebSocket and setup listeners
  Future<void> _connectWebSocket() async {
    try {
      // Get Firebase token for authentication
      final token = await _tokenManager.getValidAuthToken();
      if (token == null) {
        throw ConvoyFailure(
          message: 'No authentication token',
          details: 'Cannot connect to WebSocket without valid token',
          timestamp: DateTime.now(),
        );
      }

      // Connect to WebSocket
      await _webSocketDataSource.connect(token);

      // Setup convoy updates stream
      _webSocketSubscription?.cancel();
      _webSocketSubscription = _webSocketDataSource.convoyUpdatesStream.listen(
        (snapshot) {
          _isWebSocketConnected = true;
          _stopRestFallbackPolling(); // Stop fallback when WS is active
          _snapshotController.add((snapshot: snapshot, failure: null));
        },
        onError: (error) {
          print('❌ WebSocket convoy updates error: $error');
          _isWebSocketConnected = false;
          final failure = error is Failure
              ? error
              : ConvoyFailure(
                  message: 'WebSocket update failed',
                  details: 'Error receiving convoy updates: $error',
                  timestamp: DateTime.now(),
                  isRetryable: true,
                );
          _snapshotController.add((snapshot: null, failure: failure));

          // Start fallback polling
          if (_currentJourneyId != null) {
            _startRestFallbackPolling(_currentJourneyId!);
          }
        },
      );

      // Monitor connection state
      _webSocketDataSource.connectionStateStream.listen((state) {
        _isWebSocketConnected = state == ConvoyConnectionState.connected;

        if (state == ConvoyConnectionState.reconnecting ||
            state == ConvoyConnectionState.error) {
          // Start REST fallback during reconnection
          if (_currentJourneyId != null) {
            _startRestFallbackPolling(_currentJourneyId!);
          }
        }
      });
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _isWebSocketConnected = false;
      rethrow;
    }
  }

  /// Fetch initial snapshot via REST API (cold start)
  Future<void> _fetchInitialSnapshot(String journeyId) async {
    try {
      final snapshot = await _remoteDataSource.fetchLatestSnapshot(journeyId);
      _snapshotController.add((snapshot: snapshot, failure: null));
      print('📍 Initial snapshot loaded: ${snapshot.members.length} members');
    } catch (e) {
      print('⚠️ Failed to fetch initial snapshot: $e');
      final failure = e is Failure
          ? e
          : ConvoyFailure(
              message: 'Failed to load convoy data',
              details: 'Could not fetch initial convoy snapshot: $e',
              timestamp: DateTime.now(),
              isRetryable: true,
            );
      _snapshotController.add((snapshot: null, failure: failure));
    }
  }

  /// Start REST fallback polling when WebSocket is disconnected.
  /// No-ops if a terminal failure was already detected this session —
  /// WebSocket reconnect cycles must not silently restart a cancelled loop.
  void _startRestFallbackPolling(String journeyId) {
    if (_terminalFailureDetected) return;
    if (_fallbackPollingTimer != null) return; // Already polling

    print('🔄 Starting REST fallback polling');

    _fallbackPollingTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      try {
        final snapshot = await _remoteDataSource.fetchLatestSnapshot(journeyId);
        _snapshotController.add((snapshot: snapshot, failure: null));
      } catch (e) {
        print('⚠️ REST fallback polling failed: $e');
        if (_isTerminalPollingFailure(e)) {
          print('🛑 Terminal polling failure — cancelling fallback timer');
          _terminalFailureDetected = true;
          _stopRestFallbackPolling();
          if (!_snapshotController.isClosed) {
            _snapshotController.add((
              snapshot: null,
              failure: e is Failure ? e : ConvoyFailure.publishLocationFailed,
            ));
          }
        }
      }
    });
  }

  /// Whether this error means the polling loop should stop entirely (vs.
  /// transient network blip we should keep retrying through).
  bool _isTerminalPollingFailure(Object error) {
    if (error is! ConvoyFailure) return false;
    return error == ConvoyFailure.notJourneyMember ||
        error == ConvoyFailure.journeyNotActive ||
        error == ConvoyFailure.stopPolling;
  }

  /// Stop REST fallback polling
  void _stopRestFallbackPolling() {
    // No-op when polling isn't running. The WS snapshot listener calls this on
    // every peer update; without this guard it logged "Stopped REST fallback
    // polling" on every emission, flooding logs during an active convoy.
    if (_fallbackPollingTimer == null) return;
    _fallbackPollingTimer?.cancel();
    _fallbackPollingTimer = null;
    print('✅ Stopped REST fallback polling');
  }

  @override
  Future<({bool success, Failure? failure})> publishMyPosition({
    required String journeyId,
    required double latitude,
    required double longitude,
    required int timestamp,
    double? accuracy,
    double? altitude,
    double? heading,
    double? speed,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final locationUpdate = LocationUpdateDto.fromPosition(
        journeyId: journeyId,
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        accuracy: accuracy,
        altitude: altitude,
        heading: heading,
        speed: speed,
        metadata: metadata,
      );

      // Try WebSocket first if connected, otherwise use REST API
      if (_isWebSocketConnected) {
        try {
          await _webSocketDataSource.publishLocationUpdate(locationUpdate);
          return (success: true, failure: null);
        } catch (e) {
          print('❌ WebSocket publish failed, falling back to REST: $e');
          // Fall through to REST API
        }
      }

      // Publish via REST API as fallback or primary method
      await _remoteDataSource.publishLocation(locationUpdate);
      return (success: true, failure: null);
    } catch (e) {
      print('❌ Failed to publish location: $e');
      final failure = e is Failure ? e : ConvoyFailure.publishLocationFailed;
      return (success: false, failure: failure);
    }
  }

  @override
  Future<({ConvoySnapshot? snapshot, Failure? failure})> fetchLatestSnapshot(
    String journeyId,
  ) async {
    try {
      final snapshot = await _remoteDataSource.fetchLatestSnapshot(journeyId);
      return (snapshot: snapshot, failure: null);
    } catch (e) {
      print('❌ Failed to fetch latest snapshot: $e');
      final failure = e is Failure
          ? e
          : ConvoyFailure(
              message: 'Failed to fetch convoy data',
              details: 'Could not load latest convoy positions: $e',
              timestamp: DateTime.now(),
              isRetryable: true,
            );
      return (snapshot: null, failure: failure);
    }
  }

  @override
  Stream<ConvoyConnectionState> get connectionStateStream =>
      _webSocketDataSource.connectionStateStream;

  @override
  Stream<JourneyEndedEvent> get journeyEndedStream =>
      _webSocketDataSource.journeyEndedStream;

  @override
  Stream<ParticipantArrivedEvent> get participantArrivedStream =>
      _webSocketDataSource.participantArrivedStream;

  @override
  Stream<String> get journeyStartedStream =>
      _webSocketDataSource.journeyStartedStream;

  @override
  Stream<String> get participantAcceptedStream =>
      _webSocketDataSource.participantAcceptedStream;

  @override
  Stream<Map<String, dynamic>> get journeyInviteStream =>
      _webSocketDataSource.journeyInviteStream;

  @override
  Future<void> joinJourneyRoom(String journeyId) async {
    _currentJourneyId = journeyId;
    await _connectWebSocket();
    await _webSocketDataSource.joinJourney(journeyId);
  }

  @override
  Future<void> connectUserChannel() async {
    try {
      _userChannelActive = true;
      // Socket may already be up (e.g. mid-convoy) — connect() is a no-op then.
      if (_webSocketDataSource.isConnected) return;

      final token = await _tokenManager.getValidAuthToken();
      if (token == null) {
        print('❌ Cannot start user channel - no valid auth token');
        return;
      }
      await _webSocketDataSource.connect(token);
      print('🔌 User channel socket connected (invite delivery)');
    } catch (e) {
      print('❌ Failed to start user channel: $e');
    }
  }

  @override
  Future<void> disconnectUserChannel() async {
    _userChannelActive = false;
    // Only actually drop the socket if no journey is using it.
    if (_currentJourneyId == null) {
      await _webSocketDataSource.disconnect();
    }
  }

  @override
  Future<void> stopCoordination() async {
    print('🛑 Stopping convoy coordination...');

    // Leave journey room if active
    if (_currentJourneyId != null) {
      try {
        await _webSocketDataSource.leaveJourney(_currentJourneyId!);
        print('✅ Left journey room: $_currentJourneyId');
      } catch (e) {
        print('⚠️ Failed to leave journey: $e');
      }
    }

    // Stop REST fallback polling
    _stopRestFallbackPolling();

    // Cancel WebSocket subscription
    await _webSocketSubscription?.cancel();
    _webSocketSubscription = null;

    // Disconnect WebSocket — unless the user channel wants it kept alive so the
    // user keeps receiving journey invites on the home screen.
    if (_userChannelActive) {
      print('🔌 Keeping socket alive for user channel (invite delivery)');
    } else {
      await _webSocketDataSource.disconnect();
      print('✅ WebSocket disconnected');
    }

    // Reset state
    _isWebSocketConnected = false;
    _currentJourneyId = null;
    _terminalFailureDetected = false;

    print('✅ Convoy coordination stopped completely');
  }
}
