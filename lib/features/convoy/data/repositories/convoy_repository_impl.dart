import 'dart:async';

import '../datasources/convoy_remote_data_source.dart';
import '../datasources/convoy_websocket_data_source.dart';
import '../datasources/location_publish_ack.dart';
import '../models/location_update_dto.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
import '../../domain/entities/participant_arrived_event.dart';
import '../../domain/repositories/convoy_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/auth/token_manager.dart';
import '../../../../core/services/connectivity_service.dart';
import '../services/location_outbox_service.dart';

/// Raised when a room join/leave/handoff is superseded before it completes.
///
/// Not a user-facing failure: it means a newer attempt owns the socket, so the
/// superseded one must unwind without touching shared room state.
class StaleRoomAttempt implements Exception {
  const StaleRoomAttempt(this.attempted, this.current);

  final int attempted;
  final int current;

  @override
  String toString() => 'StaleRoomAttempt(attempt $attempted, current $current)';
}

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
    required LocationOutboxService outboxService,
    required ConnectivityService connectivityService,
    required Future<String?> Function() currentUserId,
  }) : _remoteDataSource = remoteDataSource,
       _webSocketDataSource = webSocketDataSource,
       _tokenManager = tokenManager,
       _outboxService = outboxService,
       _connectivityService = connectivityService,
       _currentUserId = currentUserId {
    _connectivitySubscription = _connectivityService.transitions.listen((
      online,
    ) {
      if (!online) return;
      unawaited(ensureLiveConnection());
    });
  }

  final ConvoyRemoteDataSource _remoteDataSource;
  final ConvoyWebSocketDataSource _webSocketDataSource;
  final TokenManager _tokenManager;
  final LocationOutboxService _outboxService;
  final ConnectivityService _connectivityService;
  final Future<String?> Function() _currentUserId;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _outboxFlushInFlight = false;
  Future<void>? _recoveryInFlight;

  StreamSubscription<ConvoySnapshot>? _webSocketSubscription;
  final StreamController<({ConvoySnapshot? snapshot, Failure? failure})>
  _snapshotController = StreamController.broadcast();

  Timer? _fallbackPollingTimer;
  bool _fallbackFetchInFlight = false;
  bool _isWebSocketConnected = false;
  String? _currentJourneyId;
  String? _joinedJourneyId;

  /// Serialises room ownership: join, leave and handoff.
  ///
  /// At most one of them may touch socket room state at a time. Previously
  /// `joinJourneyRoom` wrote `_currentJourneyId` *before* awaiting the
  /// connection and the server ack, so two joins started before either had
  /// completed both entered here and interleaved — leaving a mixed A/B state
  /// whose outcome depended on which ack arrived last.
  Future<void>? _roomOperation;

  /// Monotonic token identifying the newest room attempt.
  ///
  /// Claimed *before* the attempt queues, so a newer B invalidates A even while
  /// A is still waiting for its turn or for the server.
  int _roomEpoch = 0;

  /// Run [body] as the sole owner of room state for [epoch].
  ///
  /// Waits for any previous room operation to finish, then re-checks the epoch:
  /// an attempt superseded while queued never runs at all.
  Future<T> _asRoomOwner<T>(int epoch, Future<T> Function() body) async {
    final previous = _roomOperation;
    final gate = Completer<void>();
    _roomOperation = gate.future;
    try {
      if (previous != null) await previous.catchError((Object _) {});
      if (epoch != _roomEpoch) throw StaleRoomAttempt(epoch, _roomEpoch);
      return await body();
    } finally {
      gate.complete();
      if (identical(_roomOperation, gate.future)) _roomOperation = null;
    }
  }

  /// Tear down whatever room the socket currently holds.
  ///
  /// Called from inside [_asRoomOwner] so it can never interleave with a join.
  Future<void> _releaseCurrentRoom() async {
    final held = _joinedJourneyId ?? _currentJourneyId;
    if (held != null) {
      try {
        await _webSocketDataSource.leaveJourney(held);
      } catch (e) {
        print('⚠️ Failed to leave room $held: $e');
      }
    }
    _stopRestFallbackPolling();
    await _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    _isWebSocketConnected = false;
    _currentJourneyId = null;
    _joinedJourneyId = null;
    _terminalFailureDetected = false;
  }

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
    // Listener mode may already have connected and joined this room while the
    // user waited for the leader to start. Upgrade it to full coordination
    // without emitting a duplicate join and duplicating server broadcasts.
    if (_joinedJourneyId == journeyId && _webSocketDataSource.isConnected) {
      _currentJourneyId = journeyId;
      unawaited(_fetchInitialSnapshot(journeyId));
    } else {
      // Claim the newest-attempt slot synchronously, before any await, so a
      // second call for a different journey immediately invalidates this one.
      final epoch = ++_roomEpoch;
      unawaited(_startCoordination(journeyId, epoch));
    }

    return _snapshotController.stream;
  }

  /// Start convoy coordination with WebSocket + REST fallback
  Future<void> _startCoordination(String journeyId, int epoch) async {
    try {
      await _asRoomOwner(epoch, () async {
        // Verify we have valid authentication before starting
        await _tokenManager.getOrRefreshAuthToken();
        if (epoch != _roomEpoch) throw StaleRoomAttempt(epoch, _roomEpoch);

        // Release any room this socket still holds before claiming a new one.
        await _releaseCurrentRoom();
        if (epoch != _roomEpoch) throw StaleRoomAttempt(epoch, _roomEpoch);

        // First: Get immediate snapshot via REST (cold start)
        unawaited(_fetchInitialSnapshot(journeyId));

        // Second: Connect WebSocket for real-time updates
        await _connectWebSocket();
        if (epoch != _roomEpoch) throw StaleRoomAttempt(epoch, _roomEpoch);

        // Third: Join journey room for live updates. The data source only
        // completes this once the server's ack names *this* journey.
        await _webSocketDataSource.joinJourney(journeyId);
        if (epoch != _roomEpoch) {
          // A newer attempt owns the socket now; hand the room straight back
          // rather than publishing ourselves as joined.
          await _webSocketDataSource.leaveJourney(journeyId);
          throw StaleRoomAttempt(epoch, _roomEpoch);
        }

        // Only now is the room ours to advertise.
        _currentJourneyId = journeyId;
        _joinedJourneyId = journeyId;
      });
    } on StaleRoomAttempt catch (e) {
      print('↩️ Discarding superseded coordination start for $journeyId ($e)');
    } catch (e) {
      print('❌ Failed to start convoy coordination: $e');
      // A failed attempt must leave a deterministic state, not a mixed one.
      if (epoch == _roomEpoch) {
        _currentJourneyId = null;
        _joinedJourneyId = null;
      }
      final failure = e is Failure
          ? e
          : ConvoyFailure(
              message: 'Failed to start convoy coordination',
              details: 'Could not connect to live updates: $e',
              timestamp: DateTime.now(),
              isRetryable: true,
            );
      _snapshotController.add((snapshot: null, failure: failure));

      // Fall back to REST polling, but only while this attempt is still the
      // one that matters.
      if (epoch == _roomEpoch) {
        _currentJourneyId = journeyId;
        _startRestFallbackPolling(journeyId);
      }
    }
  }

  /// Connect to WebSocket and setup listeners
  Future<void> _connectWebSocket() async {
    try {
      // Get Firebase token for authentication
      final token = await _tokenManager.getOrRefreshAuthToken();

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

    _fallbackPollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollFallbackSnapshot(journeyId),
    );
    unawaited(_pollFallbackSnapshot(journeyId));
  }

  /// Fetch one fallback snapshot at a time. `Timer.periodic` does not await an
  /// async callback; without this guard, a slow request spawned another every
  /// three seconds and amplified an outage into a local request pile-up.
  Future<void> _pollFallbackSnapshot(String journeyId) async {
    if (_fallbackFetchInFlight ||
        _fallbackPollingTimer == null ||
        _currentJourneyId != journeyId) {
      return;
    }

    _fallbackFetchInFlight = true;
    try {
      final snapshot = await _remoteDataSource.fetchLatestSnapshot(journeyId);
      if (_fallbackPollingTimer != null &&
          _currentJourneyId == journeyId &&
          !_snapshotController.isClosed) {
        _snapshotController.add((snapshot: snapshot, failure: null));
      }
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
    } finally {
      _fallbackFetchInFlight = false;
    }
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
    final userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return (success: false, failure: ConvoyFailure.notJourneyMember);
    }

    late final LocationUpdateDto queued;
    try {
      queued = await _outboxService.enqueue(userId, locationUpdate);
    } catch (error) {
      print('❌ Could not persist location in the offline outbox: $error');
      return (success: false, failure: ConvoyFailure.publishLocationFailed);
    }

    try {
      // A reconnect handshake owns publication until peer resync and older
      // trail backfill have completed.
      await _recoveryInFlight;

      // Try WebSocket first if connected, otherwise use REST API.
      if (_isWebSocketConnected) {
        LocationPublishAck? ack;
        try {
          ack = await _webSocketDataSource.publishLocationUpdate(queued);
        } catch (e) {
          print('❌ WebSocket publish failed, falling back to REST: $e');
        }

        if (ack != null) {
          // Terminal rejection: retrying cannot succeed, so surface it as a
          // typed failure instead of looping. The point is dropped from the
          // outbox — a payload the server will never accept would otherwise
          // block every later point behind it forever.
          if (ack.outcome == LocationAckOutcome.terminal) {
            await _outboxService.acknowledge(userId, journeyId, [
              queued.clientPointId!,
            ]);
            print('🛑 Location rejected terminally (${ack.reason})');
            return (success: false, failure: _terminalAckFailure(ack));
          }

          // The server holds the point (or deliberately suppressed it).
          if (ack.isDelivered) {
            await _outboxService.acknowledge(userId, journeyId, [
              queued.clientPointId!,
            ]);
            return (success: true, failure: null);
          }

          // Retryable rejection, timeout, or an ack we could not correlate.
          // The point stays queued and we fall through to REST — this is the
          // case that used to be reported as success and silently lost.
          print(
            '↩️ WebSocket publish not accepted (${ack.reason}) — using REST',
          );
        }
      }

      // Publish via REST API as fallback or primary method.
      final delivered = await _remoteDataSource.publishLocation(queued);
      if (delivered) {
        await _outboxService.acknowledge(userId, journeyId, [
          queued.clientPointId!,
        ]);
        return (success: true, failure: null);
      }

      // Neither transport took it. The point is safely queued for backfill, so
      // this is a degraded state rather than a lost point — but it must be
      // reported as degraded, not as a success.
      print('📦 Position retained in offline outbox — live delivery deferred');
      return (success: false, failure: ConvoyFailure.publishLocationFailed);
    } catch (e) {
      print(
        '📦 Live delivery unavailable; position retained in offline outbox: $e',
      );
      if (e is ConvoyFailure &&
          (e == ConvoyFailure.journeyNotActive ||
              e == ConvoyFailure.notJourneyMember ||
              e == ConvoyFailure.stopPolling)) {
        await _outboxService.acknowledge(userId, journeyId, [
          queued.clientPointId!,
        ]);
        return (success: false, failure: e);
      }
      return (
        success: false,
        failure: e is Failure ? e : ConvoyFailure.publishLocationFailed,
      );
    }
  }

  /// Map a terminal ack reason onto the typed failure the provider already
  /// treats as "stop publishing", so a rejected payload cannot retry forever.
  Failure _terminalAckFailure(LocationPublishAck ack) {
    switch (ack.reason) {
      case 'NOT_PARTICIPANT':
      case 'UNAUTHORIZED':
        return ConvoyFailure.notJourneyMember;
      case 'JOURNEY_NOT_ACTIVE':
        return ConvoyFailure.journeyNotActive;
      default:
        return ConvoyFailure(
          message: 'Location update rejected',
          details: 'The server rejected this update (${ack.reason})',
          timestamp: DateTime.now(),
        );
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
    // Already ours and confirmed — nothing to hand over.
    if (_joinedJourneyId == journeyId && _webSocketDataSource.isConnected) {
      _currentJourneyId = journeyId;
      return;
    }

    // Claim the newest-attempt slot synchronously. Everything after this point
    // is re-validated against it, so a concurrent join for B invalidates A even
    // if A started first and is still waiting on the server.
    final epoch = ++_roomEpoch;

    await _asRoomOwner(epoch, () async {
      // Leave any stale server room first. Overwriting `_currentJourneyId`
      // while room A was still joined meant A's broadcasts kept arriving and
      // were attributed to B.
      await _releaseCurrentRoom();
      if (epoch != _roomEpoch) throw StaleRoomAttempt(epoch, _roomEpoch);

      await _connectWebSocket();
      if (epoch != _roomEpoch) throw StaleRoomAttempt(epoch, _roomEpoch);

      // Completes only on an ack naming this journey.
      await _webSocketDataSource.joinJourney(journeyId);
      if (epoch != _roomEpoch) {
        await _webSocketDataSource.leaveJourney(journeyId);
        throw StaleRoomAttempt(epoch, _roomEpoch);
      }

      _currentJourneyId = journeyId;
      _joinedJourneyId = journeyId;
    });
  }

  @override
  Future<void> connectUserChannel() async {
    try {
      _userChannelActive = true;
      // Socket may already be up (e.g. mid-convoy) — connect() is a no-op then.
      if (_webSocketDataSource.isConnected) return;

      final token = await _tokenManager.getOrRefreshAuthToken();
      await _webSocketDataSource.connect(token);
      print('🔌 User channel socket connected (invite delivery)');
    } catch (e) {
      print('❌ Failed to start user channel: $e');
    }
  }

  @override
  Future<void> ensureLiveConnection() async {
    final existing = _recoveryInFlight;
    if (existing != null) return existing;
    final recovery = _recoverLiveConnection();
    _recoveryInFlight = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_recoveryInFlight, recovery)) _recoveryInFlight = null;
    }
  }

  Future<void> _recoverLiveConnection() async {
    try {
      await _webSocketDataSource.reconnectIfDisconnected();
      await flushOfflineOutbox();
    } catch (e) {
      print('❌ Resume reconnect failed: $e');
    }
  }

  @override
  Future<void> flushOfflineOutbox() async {
    if (_outboxFlushInFlight || !_connectivityService.isOnline.value) return;
    final userId = await _currentUserId();
    if (userId == null || userId.isEmpty) return;

    _outboxFlushInFlight = true;
    try {
      for (final journeyId in _outboxService.journeyIds(userId)) {
        while (true) {
          final points = _outboxService.pending(userId, journeyId);
          if (points.isEmpty) break;
          final batchId = _outboxService.batchIdFor(points);
          await _outboxService.markAttempt(
            userId,
            journeyId,
            points.map((point) => point.clientPointId!).toList(growable: false),
          );
          final ack = await _remoteDataSource.backfillLocations(
            journeyId: journeyId,
            batchId: batchId,
            points: points
                .map(_outboxService.toBackfillPoint)
                .toList(growable: false),
          );
          final acknowledged =
              (ack['acknowledgedPointIds'] as List? ?? const [])
                  .map((value) => value.toString())
                  .toList(growable: false);
          final rejected = (ack['rejected'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (value) =>
                    value.map((key, entry) => MapEntry(key.toString(), entry)),
              )
              .toList(growable: false);
          await _outboxService.quarantineRejected(userId, journeyId, rejected);
          if (acknowledged.isEmpty && rejected.isEmpty) {
            print('⚠️ Backfill made no progress for journey $journeyId');
            break;
          }
          await _outboxService.acknowledge(userId, journeyId, acknowledged);
          print('📦 Synced ${acknowledged.length} offline points');
        }
      }
    } catch (error) {
      print('⚠️ Offline outbox flush paused: $error');
    } finally {
      _outboxFlushInFlight = false;
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

    // A stop is itself a room operation: it invalidates any join still waiting
    // for its ack, and it queues behind whatever is running so it can never
    // interleave with a half-finished handoff.
    final epoch = ++_roomEpoch;
    try {
      await _asRoomOwner(epoch, () async {
        await _releaseCurrentRoom();

        // Disconnect WebSocket — unless the user channel wants it kept alive
        // so the user keeps receiving journey invites on the home screen.
        if (_userChannelActive) {
          print('🔌 Keeping socket alive for user channel (invite delivery)');
        } else {
          await _webSocketDataSource.disconnect();
          print('✅ WebSocket disconnected');
        }
      });
    } on StaleRoomAttempt {
      // A newer join already took over; it owns teardown of what we would have
      // torn down, so there is nothing left for this stop to do.
      print('↩️ stopCoordination superseded by a newer room attempt');
    }

    print('✅ Convoy coordination stopped completely');
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _webSocketSubscription?.cancel();
    _fallbackPollingTimer?.cancel();
    await _snapshotController.close();
  }
}
