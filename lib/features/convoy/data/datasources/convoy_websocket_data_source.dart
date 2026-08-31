import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/member_position_model.dart';
import '../models/location_update_dto.dart';
import 'location_publish_ack.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
import '../../domain/entities/participant_arrived_event.dart';
import '../../domain/entities/route_updated_event.dart';
import '../../domain/entities/member_position.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/services/offline_storage_service.dart';

@visibleForTesting
bool shouldReconnectAfterDisconnect(
  Object? reason, {
  required bool heartbeatTimedOut,
}) {
  final serverDisconnect = (reason?.toString() ?? '').contains(
    'server disconnect',
  );
  return !serverDisconnect || heartbeatTimedOut;
}

/// Builds socket options that leave all reconnect attempts to the app.
@visibleForTesting
Map<String, dynamic> buildConvoySocketOptions(String firebaseToken) {
  return io.OptionBuilder()
      .setTransports(['websocket'])
      // The app owns reconnection so every attempt can refresh the Firebase
      // credential first. Socket.IO's built-in loop otherwise races this loop
      // and can reuse the expired auth payload captured at initial connection.
      .disableReconnection()
      .disableAutoConnect()
      // socket_io_client caches managers by URL. A fresh manager prevents an
      // older manager (created with reconnection enabled) from being reused.
      .enableForceNew()
      .setAuth({'token': firebaseToken})
      .build();
}

/// Structured handshake-rejection codes emitted by the backend's Socket.IO
/// auth middleware (`LocationGateway.authenticateSocket`). Kept in sync with
/// the backend's `SocketAuthErrorCode` union.
abstract class SocketAuthCode {
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const tokenRevoked = 'TOKEN_REVOKED';
  static const authTemporarilyUnavailable = 'AUTH_TEMPORARILY_UNAVAILABLE';
  static const authFailed = 'AUTH_FAILED';

  /// No `code` field was present on the failure payload — a raw transport
  /// error (unreachable host, timeout) rather than a handshake rejection.
  static const unknown = 'UNKNOWN';
}

/// A classified handshake failure, thrown by [_waitForConnection] so the
/// reconnect loop can react to *why* the handshake failed instead of
/// retrying every failure identically.
class SocketHandshakeError implements Exception {
  const SocketHandshakeError(this.code, this.message);

  final String code;
  final String message;

  /// Parses the payload carried by a `connect_error`/`error` event.
  ///
  /// The installed socket_io_client (2.0.3+1) does not translate a namespace
  /// middleware rejection (server calling `next(err)`) into a `connect_error`
  /// event the way the socket.io protocol / JS client does — it decodes the
  /// CONNECT_ERROR packet and re-emits it as a plain `error` event instead
  /// (see `Socket.onpacket` in that package). Both event sources carry the
  /// same `{code, message}` map the backend attached via `ExtendedError.data`,
  /// so both are parsed identically here.
  @visibleForTesting
  factory SocketHandshakeError.fromEventPayload(dynamic payload) {
    final data = payload is Map ? payload : null;
    final code = data?['code'] as String?;
    final message =
        (data?['message'] as String?) ??
        payload?.toString() ??
        'Connection failed';
    return SocketHandshakeError(code ?? SocketAuthCode.unknown, message);
  }

  @override
  String toString() => 'SocketHandshakeError($code: $message)';
}

@visibleForTesting
class JoinRecoveryEnvelope {
  const JoinRecoveryEnvelope({
    required this.mode,
    this.updates = const [],
    this.nextSequence,
    this.hasMore = false,
  });

  final String mode;
  final List<dynamic> updates;
  final int? nextSequence;
  final bool hasMore;

  static JoinRecoveryEnvelope? fromAcknowledgement(
    Map<String, dynamic> acknowledgement,
  ) {
    final raw = acknowledgement['recovery'];
    if (raw is! Map) return null;
    final mode = raw['mode']?.toString();
    if (mode != 'DELTA' && mode != 'SNAPSHOT_REQUIRED') return null;
    return JoinRecoveryEnvelope(
      mode: mode!,
      updates: raw['updates'] is List ? raw['updates'] as List : const [],
      nextSequence: (raw['nextSequence'] as num?)?.toInt(),
      hasMore: raw['hasMore'] == true,
    );
  }
}

/// Abstract interface for convoy WebSocket operations
abstract class ConvoyWebSocketDataSource {
  /// Connect to convoy coordination WebSocket
  Future<void> connect(String firebaseToken);

  /// Disconnect from WebSocket
  Future<void> disconnect();

  /// Force an immediate reconnect attempt if the socket exists but is down.
  ///
  /// Resets backoff timers and give-up flags first. Intended for app-resume:
  /// a client kicked by the server heartbeat monitor while backgrounded may
  /// have exhausted its reconnect budget or be waiting out a long backoff.
  Future<void> reconnectIfDisconnected();

  /// Join a journey room for real-time updates.
  ///
  /// Completes only once the server's `joined-journey` acknowledgement names
  /// **this** journey. A generic ack, or one for a different room, must never
  /// complete this call — that is how a join for A reported room B as ready.
  Future<void> joinJourney(String journeyId);

  /// Leave a journey room
  Future<void> leaveJourney(String journeyId);

  /// Publish a location update and report what the server answered.
  ///
  /// Returns a [LocationPublishAck] rather than completing unconditionally:
  /// the backend can answer `accepted: false`, and treating that as success is
  /// what dropped points out of the offline outbox without delivering them.
  Future<LocationPublishAck> publishLocationUpdate(
    LocationUpdateDto locationUpdate,
  );

  /// Stream of convoy snapshots from WebSocket updates
  Stream<ConvoySnapshot> get convoyUpdatesStream;

  /// Stream of connection state changes
  Stream<ConvoyConnectionState> get connectionStateStream;

  /// Stream of `journey-ended` events from the backend.
  /// Clients MUST stop coordinating the named journey on receiving this.
  Stream<JourneyEndedEvent> get journeyEndedStream;

  /// Stream of `participant-arrived` events. Fires whenever any participant
  /// (current user or someone else) reaches the destination. When
  /// `allArrived` is true the backend auto-completes the journey and a
  /// `journey-ended` event follows immediately.
  Stream<ParticipantArrivedEvent> get participantArrivedStream;

  /// Stream of `journey-started` events from the backend.
  /// Members who pre-joined the room should navigate to the map on receiving this.
  Stream<String> get journeyStartedStream;

  /// Stream of `participant-accepted` events. Fires when an invited member
  /// accepts.
  ///
  /// Emits the **event's own** `journeyId`, taken from the payload, so a late
  /// acceptance for a journey the user has already left cannot be attributed
  /// to the journey they are on now. Events without a `journeyId` are dropped.
  Stream<String> get participantAcceptedStream;

  /// Stream of canonical route-version commits for the joined journey.
  Stream<RouteUpdatedEvent> get routeUpdatedStream;

  /// Stream of `journey-invite` events pushed to this user's per-user room when
  /// someone invites them to a journey. Delivered on any connected socket, so
  /// the invite list can update live without a reload.
  Stream<Map<String, dynamic>> get journeyInviteStream;

  /// Send acknowledgment for received location update
  Future<void> acknowledgeUpdate(int sequenceNumber);

  /// Send heartbeat to maintain connection
  Future<void> sendHeartbeat();

  /// Request resync from a specific sequence number
  Future<void> requestResync(int fromSequence);

  /// Get current connection state
  ConvoyConnectionState get connectionState;

  /// Check if connected
  bool get isConnected;
}

/// Implementation of convoy WebSocket data source using Socket.IO
class ConvoyWebSocketDataSourceImpl implements ConvoyWebSocketDataSource {
  ConvoyWebSocketDataSourceImpl({
    this.authTokenProvider,
    this.offlineStorage,
    this.currentUserId,
  });

  /// Supplies a fresh token before a reconnect handshake. Socket.IO retains
  /// the auth payload from the original connection, which is commonly expired
  /// after an app has spent an hour in navigation/background mode.
  final Future<String> Function()? authTokenProvider;
  final OfflineStorageService? offlineStorage;
  final Future<String?> Function()? currentUserId;

  io.Socket? _socket;
  String? _currentJourneyId;
  ConvoyConnectionState _connectionState = ConvoyConnectionState.disconnected;

  // Stream controllers
  final StreamController<ConvoySnapshot> _convoyController =
      StreamController.broadcast();
  final StreamController<ConvoyConnectionState> _connectionController =
      StreamController.broadcast();
  final StreamController<JourneyEndedEvent> _journeyEndedController =
      StreamController.broadcast();
  final StreamController<ParticipantArrivedEvent>
  _participantArrivedController = StreamController.broadcast();
  final StreamController<String> _journeyStartedController =
      StreamController.broadcast();
  final StreamController<String> _participantAcceptedController =
      StreamController.broadcast();
  final StreamController<RouteUpdatedEvent> _routeUpdatedController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _journeyInviteController =
      StreamController.broadcast();

  // Convoy state
  final Map<String, MemberPosition> _members = {};
  ConvoyDestination? _destination;
  String? _destinationAddress;

  // Connection management
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect =
      false; // Flag to prevent reconnection on intentional disconnect
  // The backend uses `socket.disconnect(true)` for both logout and heartbeat
  // expiry. Socket.IO reports both as `io server disconnect`, but the backend
  // emits connection-status=TIMEOUT immediately before a heartbeat eviction.
  // Remember that signal so a temporarily stalled mobile client reconnects.
  bool _heartbeatTimedOut = false;
  static const int _maxReconnectAttempts = 10;
  static const List<int> _reconnectDelays = [1, 2, 4, 8, 15, 30]; // seconds

  /// Consecutive reconnect failures classified as
  /// [SocketAuthCode.tokenExpired]. A refreshed handshake token
  /// deterministically fixes this case, so those retries skip the normal
  /// backoff — bounded by [_maxFastTokenRetries] so a persistent clock-skew
  /// or refresh bug can't spin a tight retry loop.
  int _consecutiveTokenExpiries = 0;
  static const int _maxFastTokenRetries = 3;
  static const Duration _tokenExpiredRetryDelay = Duration(milliseconds: 300);

  /// Wall-clock time when the current socket successfully connected.
  /// Used to distinguish a healthy long-lived connection (resets failure
  /// counters) from a "connect → immediately drop" loop (trips a separate
  /// short-lived-connection circuit breaker).
  DateTime? _connectedAt;

  /// Number of consecutive connections that died within
  /// [_shortLivedConnectionThreshold] of being established. If this exceeds
  /// [_maxShortLivedConnections] we stop trying — the regular
  /// `_reconnectAttempts` counter won't catch this loop because it resets
  /// every time the TCP handshake succeeds, even if the heartbeat
  /// immediately times out.
  int _shortLivedConnections = 0;
  final Map<String, Completer<LocationPublishAck>> _pendingLocationAcks = {};

  /// Monotonic token for room ownership inside the transport.
  ///
  /// Bumped by every join and leave. A join captures it before emitting and
  /// re-checks it after the ack, so a newer attempt invalidates an older one
  /// that is still waiting — without this, two joins raced and whichever ack
  /// arrived last decided which room the socket believed it was in.
  int _roomEpoch = 0;
  Completer<Map<String, dynamic>>? _pendingResync;
  int _lastAppliedSequence = 0;
  static const int _maxShortLivedConnections = 3;
  static const Duration _shortLivedConnectionThreshold = Duration(seconds: 20);

  @override
  Stream<ConvoySnapshot> get convoyUpdatesStream => _convoyController.stream;

  @override
  Stream<ConvoyConnectionState> get connectionStateStream =>
      _connectionController.stream;

  @override
  Stream<JourneyEndedEvent> get journeyEndedStream =>
      _journeyEndedController.stream;

  @override
  Stream<ParticipantArrivedEvent> get participantArrivedStream =>
      _participantArrivedController.stream;

  @override
  Stream<String> get journeyStartedStream => _journeyStartedController.stream;

  /// Test seam for [_journeyIdFromStartedPayload].
  ///
  /// The parsing is the whole fix — exposing it keeps the contract testable
  /// without standing up a socket.
  @visibleForTesting
  static String? debugJourneyIdFromStartedPayload(Object? data) =>
      _journeyIdFromStartedPayload(data);

  /// Extract the journey id from a `journey-started` payload.
  ///
  /// Tolerates the nested shape the gateway actually sends plus a flat
  /// fallback, and returns null for anything unrecognised so a malformed event
  /// is dropped rather than silently attributed to the current room.
  static String? _journeyIdFromStartedPayload(Object? data) {
    String? read(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    if (data is! Map) return null;
    final journey = data['journey'];
    if (journey is Map) {
      return read(journey['journeyId']) ?? read(journey['id']);
    }
    return read(data['journeyId']) ?? read(data['id']);
  }

  /// Test seam for [_journeyIdFromParticipantAcceptedPayload].
  @visibleForTesting
  static String? debugJourneyIdFromParticipantAcceptedPayload(Object? data) =>
      _journeyIdFromParticipantAcceptedPayload(data);

  /// Extract the journey id from a `participant-accepted` payload.
  ///
  /// The backend stamps it in `LocationGateway.broadcastParticipantAccepted`.
  /// Returns null for anything unrecognised so the event is dropped rather
  /// than being attributed to whatever room we happen to believe we are in —
  /// which is how a late acceptance for journey A refreshed journey B.
  static String? _journeyIdFromParticipantAcceptedPayload(Object? data) {
    if (data is! Map) return null;
    final value = data['journeyId'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Stream<String> get participantAcceptedStream =>
      _participantAcceptedController.stream;

  @override
  Stream<RouteUpdatedEvent> get routeUpdatedStream =>
      _routeUpdatedController.stream;

  @override
  Stream<Map<String, dynamic>> get journeyInviteStream =>
      _journeyInviteController.stream;

  @override
  ConvoyConnectionState get connectionState => _connectionState;

  @override
  bool get isConnected => _socket?.connected ?? false;

  /// Guards against opening duplicate sockets when multiple callers race to
  /// connect (e.g. the user channel on home and convoy coordination). All
  /// concurrent connect() calls await the same in-flight connection.
  Future<void>? _connectingFuture;

  @override
  Future<void> connect(String firebaseToken) {
    if (isConnected) return Future.value();

    // A connection is already being established — reuse it instead of opening
    // a second socket.
    final inFlight = _connectingFuture;
    if (inFlight != null) return inFlight;

    final future = _doConnect(firebaseToken);
    _connectingFuture = future;
    return future.whenComplete(() => _connectingFuture = null);
  }

  Future<void> _doConnect(String firebaseToken) async {
    try {
      _intentionalDisconnect = false; // Reset flag when starting new connection
      // Fresh user-initiated connection — clear the short-lived counter so a
      // prior bad session doesn't immediately kill this one.
      _shortLivedConnections = 0;
      _consecutiveTokenExpiries = 0;
      _updateConnectionState(ConvoyConnectionState.connecting);

      // Dispose any stale socket before creating a new one so we never leak an
      // orphaned connection that lingers in rooms on the server.
      if (_socket != null) {
        _socket!.dispose();
        _socket = null;
      }

      // Create Socket.IO client with authentication
      _socket = io.io(
        '${AppConfig.webSocketUrl}/location',
        buildConvoySocketOptions(firebaseToken),
      );

      _setupEventListeners();

      // Connect to WebSocket
      _socket!.connect();

      // Wait for connection with timeout
      await _waitForConnection();

      _reconnectAttempts = 0; // Reset on successful connection
      _startHeartbeat();
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _updateConnectionState(ConvoyConnectionState.error);
      throw ConvoyFailure(
        message: 'Failed to connect to convoy coordination',
        details: 'WebSocket connection failed: $e',
        timestamp: DateTime.now(),
        isRetryable: true,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true; // Set flag to prevent reconnection
    _stopHeartbeat();
    _stopReconnectTimer();

    if (_socket != null) {
      if (_currentJourneyId != null) {
        await leaveJourney(_currentJourneyId!);
      }

      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _updateConnectionState(ConvoyConnectionState.disconnected);
  }

  /// Temporary room-join race diagnostics ([ROOM-DEBUG] — mirrors the backend
  /// gateway's instrumentation). Debug builds only: event payloads must not
  /// reach release logs. Delete this and its call sites once the race is
  /// confirmed fixed.
  void _roomDebug(String message) {
    if (kDebugMode) {
      print('[ROOM-DEBUG] $message @ ${DateTime.now().toIso8601String()}');
    }
  }

  @override
  Future<void> joinJourney(String journeyId) async {
    if (!isConnected) {
      throw ConvoyFailure(
        message: 'Cannot join journey - not connected',
        details: 'WebSocket is not connected',
        timestamp: DateTime.now(),
      );
    }

    // Claim ownership of the room handoff before anything is emitted. Room
    // identity is *not* assigned here: `_currentJourneyId` used to be written
    // before the await, so a join for A advertised itself as the current room
    // while the server was still deciding, and a concurrent join for B then
    // overwrote it mid-flight.
    final epoch = ++_roomEpoch;

    final durableCursor = await _loadSequenceCursor(journeyId);

    // Await joined-journey confirmation so we know whether the server actually
    // added us to the room (vs silently rejecting with an error event).
    final completer = Completer<Map<String, dynamic>>();

    late void Function(dynamic) onJoined;
    onJoined = (data) {
      // The backend's ack carries the room it joined
      // (location.gateway.ts handleJoinJourney → `joined-journey`).
      // An ack for a *different* journey must not complete this attempt.
      if (data is! Map<dynamic, dynamic>) {
        _roomDebug('⚠️ joined-journey ACK without journeyId ignored');
        return;
      }
      final ackJourneyId = data['journeyId']?.toString();
      if (ackJourneyId != null && ackJourneyId != journeyId) {
        _roomDebug(
          '⚠️ joined-journey ACK for $ackJourneyId ignored while joining '
          '$journeyId',
        );
        return;
      }
      if (ackJourneyId == null) {
        _roomDebug('⚠️ joined-journey ACK without journeyId ignored');
        return;
      }
      _socket!.off('joined-journey', onJoined);
      _roomDebug('✅ joined-journey ACK for $journeyId');
      if (!completer.isCompleted) {
        final acknowledgement = <String, dynamic>{};
        data.forEach((dynamic key, dynamic value) {
          acknowledgement[key.toString()] = value;
        });
        completer.complete(acknowledgement);
      }
    };

    _socket!.on('joined-journey', onJoined);
    _socket!.emit('join-journey', {
      'journeyId': journeyId,
      if (durableCursor > 0) 'lastLocationSequence': durableCursor,
    });

    _roomDebug('🔌 emit join-journey $journeyId');

    // A missing acknowledgement means room membership is unknown. Treat it as
    // a retryable failure instead of reporting listener mode as ready and then
    // silently missing journey-started events.
    late final Map<String, dynamic> acknowledgement;
    try {
      acknowledgement = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw ConvoyFailure(
            message: 'Live updates are reconnecting',
            details: 'The server did not confirm journey room membership',
            timestamp: DateTime.now(),
            isRetryable: true,
          );
        },
      );
    } finally {
      _socket?.off('joined-journey', onJoined);
    }

    // A newer join or an explicit leave took over while the server answered.
    // Give the room straight back rather than installing it as ours.
    if (epoch != _roomEpoch) {
      _roomDebug('↩️ discarding superseded join for $journeyId');
      try {
        _socket?.emit('leave-journey', {'journeyId': journeyId});
      } catch (_) {
        // Socket already gone; the server drops the room with it.
      }
      throw ConvoyFailure(
        message: 'Live updates are reconnecting',
        details: 'A newer journey room took over this connection',
        timestamp: DateTime.now(),
        isRetryable: true,
      );
    }

    // Only now is this room genuinely ours. Older servers do not include a
    // recovery envelope, so retain the original request-resync fallback while
    // deployments roll forward independently.
    _currentJourneyId = journeyId;
    await _applyJoinRecovery(acknowledgement, durableCursor);
  }

  @override
  Future<void> leaveJourney(String journeyId) async {
    // Leaving invalidates any join still waiting for its ack, including a join
    // for this same room that has not completed yet.
    _roomEpoch++;
    if (!isConnected) {
      if (_currentJourneyId == journeyId) _currentJourneyId = null;
      return;
    }

    _socket!.emit('leave-journey', {'journeyId': journeyId});
    if (_currentJourneyId == journeyId) _currentJourneyId = null;

    // Clear convoy state
    _members.clear();
    _destination = null;
    _destinationAddress = null;

    print('🔌 Left journey: $journeyId');
  }

  @override
  Future<LocationPublishAck> publishLocationUpdate(
    LocationUpdateDto locationUpdate,
  ) async {
    if (!isConnected) {
      throw ConvoyFailure(
        message: 'Cannot publish location - not connected',
        details: 'WebSocket is not connected',
        timestamp: DateTime.now(),
        isRetryable: true,
      );
    }

    // Convert DTO to WebSocket event format
    final payload = <String, dynamic>{
      'journeyId': locationUpdate.journeyId,
      'location': {
        'latitude': locationUpdate.location.latitude,
        'longitude': locationUpdate.location.longitude,
      },
      'timestamp': locationUpdate.timestamp,
      if (locationUpdate.clientPointId != null)
        'clientPointId': locationUpdate.clientPointId,
      if (locationUpdate.accuracy != null) 'accuracy': locationUpdate.accuracy,
      if (locationUpdate.altitude != null) 'altitude': locationUpdate.altitude,
      if (locationUpdate.heading != null) 'heading': locationUpdate.heading,
      if (locationUpdate.speed != null) 'speed': locationUpdate.speed,
      if (locationUpdate.metadata != null) 'metadata': locationUpdate.metadata,
    };

    final pointId = locationUpdate.clientPointId;
    if (pointId == null) {
      // Uncorrelatable by construction: there is nothing to match an ack
      // against, so this cannot be reported as delivered.
      _socket!.emit('location-update', payload);
      return LocationPublishAck.malformed;
    }
    final completer = Completer<LocationPublishAck>();
    _pendingLocationAcks[pointId] = completer;
    _socket!.emit('location-update', payload);
    try {
      return await completer.future.timeout(
        const Duration(seconds: 10),
        // A timeout is *not* a delivery. The point stays queued and the caller
        // falls back to REST — raising this window would only hide the defect.
        onTimeout: () => LocationPublishAck.timedOut,
      );
    } finally {
      _pendingLocationAcks.remove(pointId);
    }
  }

  @override
  Future<void> acknowledgeUpdate(int sequenceNumber) async {
    if (!isConnected) return;

    _socket!.emit('acknowledge', {'sequenceNumber': sequenceNumber});
  }

  @override
  Future<void> sendHeartbeat() async {
    if (!isConnected) return;

    _socket!.emit('heartbeat', {});
  }

  @override
  Future<void> requestResync(int fromSequence) async {
    if (!isConnected) return;
    await _performResync(fromSequence);
  }

  /// Setup event listeners for WebSocket
  void _setupEventListeners() {
    if (_socket == null) return;

    // Connection events
    _socket!.onConnect((_) {
      print('✅ WebSocket connected');
      _heartbeatTimedOut = false;
      _connectedAt = DateTime.now();
      _updateConnectionState(ConvoyConnectionState.connected);

      // Room rejoin is deliberately owned by _attemptReconnect(), which awaits
      // joined-journey before resync/backfill. Emitting here as well caused two
      // joins and duplicate snapshots on every transport recovery.
    });

    _socket!.onDisconnect((reason) {
      print('❌ WebSocket disconnected (reason: $reason)');
      _recordConnectionLifetime();

      if (_intentionalDisconnect) {
        print('🔌 Intentional disconnect - not attempting to reconnect');
        _updateConnectionState(ConvoyConnectionState.disconnected);
        return;
      }

      // A server-initiated disconnect is terminal — do NOT reconnect. The
      // backend force-disconnects this user's sockets on logout (BE-FIX-4,
      // server-side `disconnectSockets`), which Socket.IO surfaces as the
      // 'io server disconnect' reason. Reconnecting here would immediately
      // re-handshake with a now-revoked token and churn until the short-lived
      // guard trips; the auth/logout flow tears down the rest. Network drops
      // ('ping timeout' / 'transport close' / 'transport error') fall through
      // to the reconnect path below.
      final reasonStr = reason?.toString() ?? '';
      if (!shouldReconnectAfterDisconnect(
        reason,
        heartbeatTimedOut: _heartbeatTimedOut,
      )) {
        print('🔌 Server-initiated disconnect ($reasonStr) - not reconnecting');
        _intentionalDisconnect = true;
        _stopReconnectTimer();
        _updateConnectionState(ConvoyConnectionState.disconnected);
        return;
      }

      _heartbeatTimedOut = false;

      // Give up if too many recent connections died in their crib — this is
      // the connect→heartbeat-timeout→reconnect loop. The regular attempt
      // counter doesn't catch it because the TCP handshake itself succeeds.
      if (_shortLivedConnections >= _maxShortLivedConnections) {
        if (_currentJourneyId != null) {
          print(
            '⚠️ Live journey connection is unstable; continuing at max backoff',
          );
          _shortLivedConnections = _maxShortLivedConnections;
          _updateConnectionState(ConvoyConnectionState.reconnecting);
          _scheduleReconnect(forceMaxDelay: true);
          return;
        }
        print(
          '🛑 Giving up reconnect: $_shortLivedConnections consecutive '
          'short-lived connections (auth or journey state is bad)',
        );
        _intentionalDisconnect = true;
        _updateConnectionState(ConvoyConnectionState.error);
        return;
      }

      _updateConnectionState(ConvoyConnectionState.reconnecting);
      _scheduleReconnect();
    });

    // Connection status event
    _socket!.on('connection-status', (data) {
      final status = data['status'] as String?;
      if (status == 'CONNECTED') {
        _updateConnectionState(ConvoyConnectionState.connected);
      } else if (status == 'TIMEOUT') {
        _heartbeatTimedOut = true;
      }
      print('🔌 Connection status: $status - ${data['message']}');
    });

    // Error events — covers both transport errors and server-emitted `error` events
    // (e.g. join-journey rejected because isParticipant check failed)
    _socket!.onError((error) {
      print('❌ WebSocket error: $error');
      _updateConnectionState(ConvoyConnectionState.error);
    });
    _socket!.on('error', (data) {
      final message = data is Map ? data['message'] : data?.toString();
      print('❌ Server error: $message');
    });

    // Journey lifecycle events
    _socket!.on('joined-journey', (data) {
      final journeyId = data is Map ? data['journeyId'] : null;
      print('✅ Joined journey: $journeyId');
      // Do not emit a placeholder snapshot here. Its (0,0) destination causes
      // the map to remove otherwise-valid peer markers for a frame during cold
      // start/reconnect. `latest-locations`, live updates, and the parallel REST
      // cold-start fetch provide the first authoritative snapshot.
    });

    _socket!.on('left-journey', (data) {
      print('✅ Left journey: ${data['journeyId']}');
    });

    _socket!.on('journey-ended', (data) {
      print('🏁 Journey ended: $data');

      // Identity comes from the payload only. Falling back to the room we
      // believe we are in let an event emitted for a room we had just left be
      // attributed to the one we had just joined.
      final journeyId = JourneyEndedEvent.journeyIdFrom(data);
      if (journeyId == null) {
        _roomDebug('⚠️ journey-ended DROPPED (no journeyId in payload)');
      } else {
        final payload = data is Map<String, dynamic>
            ? data
            : <String, dynamic>{};
        if (!_journeyEndedController.isClosed) {
          _journeyEndedController.add(
            JourneyEndedEvent.fromJson(journeyId, payload),
          );
        }
      }

      // Clear convoy state and notify listeners
      _members.clear();
      _emitConvoySnapshot();
    });

    _socket!.on('journey-started', (data) {
      _roomDebug(
        '🚀 journey-started RECV currentJourney=$_currentJourneyId data=$data',
      );
      // Identity comes from the payload, never from mutable local state. The
      // backend emits `{journey: {journeyId, journeyName, status}, timestamp}`
      // (location.gateway.ts broadcastJourneyStarted / journey.service.ts).
      // Substituting `_currentJourneyId` meant an event from a room we had
      // just left was reported as the room we had just joined.
      final eventJourneyId = _journeyIdFromStartedPayload(data);
      if (eventJourneyId == null) {
        _roomDebug('⚠️ journey-started DROPPED (no journeyId in payload)');
        return;
      }
      // A late event from a previous room must not activate the current one.
      if (_currentJourneyId != null && eventJourneyId != _currentJourneyId) {
        _roomDebug(
          '⚠️ journey-started IGNORED (event=$eventJourneyId '
          'current=$_currentJourneyId)',
        );
        return;
      }
      if (!_journeyStartedController.isClosed) {
        _journeyStartedController.add(eventJourneyId);
      }
    });

    _socket!.on('participant-accepted', (data) {
      final userId = data is Map ? data['userId'] : null;
      // Identity comes from the payload, never from `_currentJourneyId`.
      // Attributing the event to whatever room we happen to believe we are in
      // meant a late acceptance for journey A refreshed journey B's roster.
      // The backend stamps `journeyId` in
      // `LocationGateway.broadcastParticipantAccepted`.
      final journeyId = _journeyIdFromParticipantAcceptedPayload(data);
      _roomDebug(
        '🤝 participant-accepted RECV userId=$userId journeyId=$journeyId '
        'currentJourney=$_currentJourneyId',
      );
      if (journeyId == null) {
        // A server that predates the journey-scoped contract. Dropping is the
        // safe failure: the roster still refreshes on the next explicit read,
        // whereas guessing refreshes the wrong journey.
        _roomDebug('⚠️ participant-accepted DROPPED (no journeyId in payload)');
        return;
      }
      if (!_participantAcceptedController.isClosed) {
        _participantAcceptedController.add(journeyId);
      }
    });

    _socket!.on('route-updated', (data) {
      final event = RouteUpdatedEvent.fromPayload(data);
      if (event == null || event.journeyId != _currentJourneyId) return;
      if (!_routeUpdatedController.isClosed) {
        _routeUpdatedController.add(event);
      }
    });

    // User-scoped event — arrives on any connected socket (we auto-join the
    // backend's user room on connect), independent of the current journey.
    _socket!.on('journey-invite', (data) {
      print('📨 Journey invite received: $data');
      if (data is Map && !_journeyInviteController.isClosed) {
        _journeyInviteController.add(data.cast<String, dynamic>());
      }
    });

    // Participant events
    _socket!.on('participant-joined', (data) {
      final userId = data['userId'] as String?;
      print('👋 Participant joined: $userId');
    });

    _socket!.on('participant-left', (data) {
      final userId = data['userId'] as String?;
      if (userId != null) {
        _members.remove(userId);
        _emitConvoySnapshot();
      }
      print('👋 Participant left: $userId');
    });

    _socket!.on('participant-disconnected', (data) {
      final userId = data['userId'] as String?;
      if (userId != null) {
        // Mark as stale rather than removing immediately
        final member = _members[userId];
        if (member != null) {
          _members[userId] = member.copyWith(
            connectionState: 'RECONNECTING',
            lastSeenAt: DateTime.now().millisecondsSinceEpoch,
          );
          _emitConvoySnapshot();
        }
      }
      print('🔌 Participant disconnected: $userId');
    });

    _socket!.on('participant-connection-changed', (data) {
      if (data is! Map) return;
      final userId = data['userId']?.toString();
      final member = userId == null ? null : _members[userId];
      if (member == null) return;
      _members[userId!] = member.copyWith(
        connectionState: data['state']?.toString(),
        lastSeenAt: _parseEventTimestamp(data['lastSeenAt']),
      );
      _emitConvoySnapshot();
    });

    // Location update events
    _socket!.on('location-update', (data) {
      if (data is! Map) return;
      _handleLocationUpdate(data.cast<String, dynamic>());
    });

    _socket!.on('location-update-ack', (data) {
      if (data is! Map) return;
      final pointId = data['clientPointId']?.toString();

      // The server answers per `clientPointId`. An ack naming a point we are
      // not waiting on belongs to a publish that already timed out (or to a
      // point we never sent) — completing an arbitrary pending publish with it
      // would report the wrong point as delivered.
      if (pointId != null) {
        final pending = _pendingLocationAcks[pointId];
        if (pending == null) {
          print('⚠️ Unmatched location-update-ack for $pointId — ignored');
          return;
        }
        final ack = LocationPublishAck.fromPayload(data);
        if (!pending.isCompleted) pending.complete(ack);
        print('📬 location-update-ack $pointId → $ack');
        return;
      }

      // No correlation id. The gateway always echoes `clientPointId`, so this
      // is a malformed answer: it is reported as a failure (the point stays
      // queued) rather than being guessed onto a pending publish.
      if (_pendingLocationAcks.length == 1) {
        final pending = _pendingLocationAcks.values.first;
        if (!pending.isCompleted) {
          pending.complete(LocationPublishAck.malformed);
        }
      }
      print('⚠️ location-update-ack without clientPointId — treated as failed');
    });

    _socket!.on('latest-locations', (data) {
      if (data is! Map) return;
      _handleLatestLocations(data.cast<String, dynamic>());
    });

    // Convoy alerts
    _socket!.on('lag-alert', (data) {
      if (data is! Map) return;
      final userId = data['userId'] as String?;
      // Guard malformed alerts: the backend sometimes emits a lag-alert with a
      // null userId. Without this guard we logged "Lag alert for null" noise
      // and pointlessly walked the members map on every such event.
      if (userId == null) return;
      final severity = data['severity'] as String?;
      print('⚠️ Lag alert for $userId: $severity');

      // Update member status if exists
      if (_members.containsKey(userId)) {
        final member = _members[userId]!;
        _members[userId] = member.copyWith(statusChange: 'LAG');
        _emitConvoySnapshot();
      }
    });

    _socket!.on('participant-arrived', (data) {
      if (data is! Map) return;
      final event = ParticipantArrivedEvent.fromJson(
        data.cast<String, dynamic>(),
      );
      print(
        '🎯 Participant arrived: ${event.userId} '
        '(${event.arrivedCount}/${event.totalCount}, allArrived=${event.allArrived})',
      );

      final existing = _members[event.userId];
      if (existing != null) {
        _members[event.userId] = existing.copyWith(statusChange: 'ARRIVED');
        _emitConvoySnapshot();
      }

      if (!_participantArrivedController.isClosed) {
        _participantArrivedController.add(event);
      }
    });

    // Acknowledgment events
    _socket!.on('acknowledge-received', (data) {
      final sequenceNumber = data['sequenceNumber'] as int?;
      print('✅ Acknowledge received: $sequenceNumber');
    });

    _socket!.on('heartbeat-ack', (data) {
      // Heartbeat acknowledged - connection is alive
    });

    // Resync events
    _socket!.on('resync-data', (data) {
      if (data is! Map) return;
      final page = data.cast<String, dynamic>();
      final count = page['count'] as int?;
      print('🔄 Resync data received: $count updates');
      final pending = _pendingResync;
      if (pending != null && !pending.isCompleted) {
        pending.complete(page);
      }
    });
  }

  /// Handle incoming location update
  void _handleLocationUpdate(Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String?;
      if (userId == null) return;

      final locationMap = (data['location'] as Map?)?.cast<String, dynamic>();
      if (locationMap == null) return;

      // Convert WebSocket format to MemberPosition
      final memberData = {
        'userId': userId,
        'latitude': locationMap['latitude'],
        'longitude': locationMap['longitude'],
        'timestamp': data['timestamp'],
        'accuracy': data['accuracy'],
        'heading': data['heading'],
        'speed': data['speed'],
        'altitude': data['altitude'],
        'sequenceNumber': data['sequenceNumber'],
        'priority': data['priority'],
        'metadata': data['metadata'],
      };

      final position = MemberPositionModel.fromJson(memberData);
      final entity = position.toEntity();
      final existing = _members[userId];
      if (existing == null || entity.timestamp >= existing.timestamp) {
        _members[userId] = entity;
      }
      final sequence = entity.sequenceNumber;
      if (sequence != null && sequence > _lastAppliedSequence) {
        _lastAppliedSequence = sequence;
        unawaited(_persistSequenceCursor());
      }
      print(
        '📍 Peer location update from $userId '
        '(${_members.length} members in convoy)',
      );

      // Acknowledge the update
      final sequenceNumber = data['sequenceNumber'] as int?;
      if (sequenceNumber != null) {
        acknowledgeUpdate(sequenceNumber);
      }

      _emitConvoySnapshot();
    } catch (e) {
      print('❌ Failed to handle location update: $e');
    }
  }

  /// Handle latest locations event (initial state)
  void _handleLatestLocations(Map<String, dynamic> data) {
    try {
      final locationsRaw = data['participants'];
      final locations = locationsRaw is Map
          ? locationsRaw.cast<String, dynamic>()
          : null;
      final destinationRaw = data['destination'];
      final destination = destinationRaw is Map
          ? destinationRaw.cast<String, dynamic>()
          : null;
      final destinationAddress = data['destinationAddress'] as String?;

      // Merge the snapshot into the members map rather than clearing it. The
      // snapshot can be incomplete (it only reflects what the server had cached
      // at that moment), and it is broadcast to the whole room on every join —
      // clearing here would wipe peers we've already received via live
      // `location-update` events and reset everyone to a stale snapshot.
      if (locations != null) {
        for (final entry in locations.entries) {
          final userId = entry.key as String?;
          if (userId == null) continue;
          final locationData = entry.value is Map
              ? (entry.value as Map).cast<String, dynamic>()
              : null;
          if (locationData == null) continue;

          try {
            // Coordinates arrive nested under 'location', not as flat keys.
            final nested = (locationData['location'] as Map?)
                ?.cast<String, dynamic>();
            final lat = nested != null
                ? (nested['latitude'] as num?)?.toDouble()
                : (locationData['latitude'] as num?)?.toDouble();
            final lng = nested != null
                ? (nested['longitude'] as num?)?.toDouble()
                : (locationData['longitude'] as num?)?.toDouble();

            if (lat == null || lng == null) continue;

            // Prefer an explicit userId in the payload (added in a future
            // backend pass); for now the key is the internal participantId.
            final memberId = locationData['userId'] as String? ?? userId;

            final position = MemberPositionModel.fromJson({
              'userId': memberId,
              'latitude': lat,
              'longitude': lng,
              'timestamp': locationData['timestamp'],
              'accuracy': locationData['accuracy'],
              'heading': locationData['heading'],
              'speed': locationData['speed'],
              'altitude': locationData['altitude'],
              'sequenceNumber': locationData['sequenceNumber'],
              'priority': locationData['priority'],
              'connectionState': locationData['connectionState'],
              'lastSeenAt': locationData['lastSeenAt'],
            }).toEntity();

            // Upsert: never let an older snapshot position overwrite a fresher
            // one we already have from a live update.
            final existing = _members[memberId];
            if (existing == null || position.timestamp >= existing.timestamp) {
              _members[memberId] = position;
            }
          } catch (e) {
            print('⚠️ Failed to parse location for $userId: $e');
          }
        }
      }

      // Update destination
      if (destination != null) {
        _destination = ConvoyDestination(
          latitude: (destination['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude: (destination['longitude'] as num?)?.toDouble() ?? 0.0,
        );
      }
      _destinationAddress = destinationAddress;

      _emitConvoySnapshot();
      print('📍 Latest locations loaded: ${_members.length} members');
    } catch (e) {
      print('❌ Failed to handle latest locations: $e');
    }
  }

  Future<int> _loadSequenceCursor(String journeyId) async {
    var cursor = 0;
    final storage = offlineStorage;
    final userProvider = currentUserId;
    if (storage != null && userProvider != null) {
      final userId = await userProvider();
      final session = userId == null
          ? null
          : storage.loadSession(userId, journeyId);
      cursor = (session?['lastAppliedSequence'] as num?)?.toInt() ?? 0;
    }
    _lastAppliedSequence = cursor;
    return cursor;
  }

  Future<void> _applyJoinRecovery(
    Map<String, dynamic> acknowledgement,
    int durableCursor,
  ) async {
    final recovery = JoinRecoveryEnvelope.fromAcknowledgement(acknowledgement);
    if (recovery == null) {
      if (durableCursor > 0) await _performResync(durableCursor);
      return;
    }
    if (recovery.mode != 'DELTA') {
      // The repository starts a canonical REST snapshot in parallel with the
      // join. It repairs route, membership and current positions for missing
      // or excessively old cursors without delaying room readiness.
      return;
    }

    for (final raw in recovery.updates) {
      if (raw is! Map) continue;
      _handleLocationUpdate(
        raw.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    final next = recovery.nextSequence ?? durableCursor;
    if (next > _lastAppliedSequence) {
      _lastAppliedSequence = next;
      await _persistSequenceCursor();
    }
    if (recovery.hasMore) {
      await _performResync(next);
    }
  }

  Future<void> _performResync(int fromSequence) async {
    var cursor = fromSequence;
    while (isConnected) {
      final completer = Completer<Map<String, dynamic>>();
      _pendingResync = completer;
      _socket!.emit('request-resync', {'fromSequence': cursor, 'limit': 500});
      late final Map<String, dynamic> page;
      try {
        page = await completer.future.timeout(const Duration(seconds: 15));
      } finally {
        if (identical(_pendingResync, completer)) _pendingResync = null;
      }

      final updates = page['updates'] as List? ?? const [];
      for (final raw in updates) {
        if (raw is! Map) continue;
        final update = raw.map((key, value) => MapEntry(key.toString(), value));
        _handleLocationUpdate(update);
      }
      final next = (page['nextSequence'] as num?)?.toInt() ?? cursor;
      if (next > _lastAppliedSequence) {
        _lastAppliedSequence = next;
        await _persistSequenceCursor();
      }
      cursor = next;
      if (page['hasMore'] != true) break;
    }
  }

  Future<void> _persistSequenceCursor() async {
    final storage = offlineStorage;
    final userProvider = currentUserId;
    final journeyId = _currentJourneyId;
    if (storage == null || userProvider == null || journeyId == null) return;
    final userId = await userProvider();
    if (userId == null) return;
    await storage.mergeSession(userId, journeyId, {
      'lastAppliedSequence': _lastAppliedSequence,
    });
  }

  int? _parseEventTimestamp(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ??
          DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    return null;
  }

  /// Emit convoy snapshot to listeners
  void _emitConvoySnapshot() {
    if (_currentJourneyId == null) return;

    final snapshot = ConvoySnapshot(
      journeyId: _currentJourneyId!,
      members: Map.from(_members),
      destination:
          _destination ?? const ConvoyDestination(latitude: 0, longitude: 0),
      destinationAddress: _destinationAddress ?? 'Unknown destination',
      timestamp: DateTime.now(),
    );

    _convoyController.add(snapshot);
  }

  /// Wait for WebSocket connection with timeout
  Future<void> _waitForConnection() async {
    const timeout = Duration(seconds: 10);
    final completer = Completer<void>();
    final socket = _socket!;

    void onConnect(_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    void onConnectError(dynamic error) {
      if (!completer.isCompleted) {
        completer.completeError(SocketHandshakeError.fromEventPayload(error));
      }
    }

    socket.on('connect', onConnect);
    // Listen on both — see [SocketHandshakeError.fromEventPayload] for why a
    // handshake rejection surfaces as `error` rather than `connect_error` on
    // this socket_io_client version.
    socket.on('connect_error', onConnectError);
    socket.on('error', onConnectError);

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          const SocketHandshakeError(
            SocketAuthCode.unknown,
            'Connection timeout',
          ),
        );
      }
    });

    try {
      await completer.future;
    } finally {
      // These listeners are re-added on every connect/reconnect attempt —
      // without removing them, a long-lived socket that reconnects many
      // times over a journey accumulates one dead listener pair per attempt.
      timer.cancel();
      socket.off('connect', onConnect);
      socket.off('connect_error', onConnectError);
      socket.off('error', onConnectError);
    }
  }

  /// Start heartbeat timer
  void _startHeartbeat() {
    _stopHeartbeat();
    // Backend HEARTBEAT_TIMEOUT_MS=7000 — send every 4 s to stay well inside
    // the 7 s window regardless of network jitter.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      sendHeartbeat();
    });
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect({bool forceMaxDelay = false}) {
    if (_intentionalDisconnect) {
      print('🔌 Skipping reconnect - intentional disconnect');
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts &&
        _currentJourneyId == null) {
      _updateConnectionState(ConvoyConnectionState.error);
      return;
    }

    _stopReconnectTimer();

    final delayIndex = forceMaxDelay
        ? _reconnectDelays.length - 1
        : math.min(_reconnectAttempts, _reconnectDelays.length - 1);
    final delay = Duration(seconds: _reconnectDelays[delayIndex]);

    print(
      '🔄 Scheduling reconnect attempt ${_reconnectAttempts + 1} in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _attemptReconnect();
    });
  }

  /// Stop reconnect timer
  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  @override
  Future<void> reconnectIfDisconnected() async {
    if (_socket == null || isConnected) return;

    // Clear give-up state: the short-lived-connection breaker or exhausted
    // attempt budget may have latched while the app was suspended, and a
    // pending backoff timer would otherwise delay recovery after resume.
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    _shortLivedConnections = 0;
    _consecutiveTokenExpiries = 0;
    _stopReconnectTimer();
    await _attemptReconnect();
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (isConnected || _intentionalDisconnect) return;

    try {
      print('🔄 Attempting reconnect...');
      _updateConnectionState(ConvoyConnectionState.reconnecting);

      // Refresh the handshake credential before reconnecting. Reusing the
      // token captured when the socket was first created causes an otherwise
      // valid session to enter a connect/auth-failure loop after token expiry.
      final tokenProvider = authTokenProvider;
      if (tokenProvider != null) {
        final token = await tokenProvider();
        _socket?.auth = {'token': token};
      }

      // Try to reconnect
      _socket?.connect();
      await _waitForConnection();

      // Rejoin journey if we were in one
      if (_currentJourneyId != null) {
        await joinJourney(_currentJourneyId!);
      }

      _reconnectAttempts = 0;
      _consecutiveTokenExpiries = 0;
    } catch (e) {
      print('❌ Reconnect failed: $e');

      // The token fetched above is deterministically stale-fixing for an
      // expired-token rejection, so this failure mode gets a fast, bounded
      // retry instead of the normal backoff — a live journey should not sit
      // on a dead credential for up to 30s waiting for the next scheduled
      // attempt. Anything else (revoked/invalid token, backend auth outage,
      // network failure) falls through to the standard backoff below; this
      // layer never signs the user out — that decision belongs solely to the
      // REST auth/refresh path (see TokenManager.onAuthLost).
      if (e is SocketHandshakeError &&
          e.code == SocketAuthCode.tokenExpired &&
          _consecutiveTokenExpiries < _maxFastTokenRetries) {
        _consecutiveTokenExpiries++;
        _stopReconnectTimer();
        _reconnectTimer = Timer(_tokenExpiredRetryDelay, _attemptReconnect);
        return;
      }

      _consecutiveTokenExpiries = 0;
      _scheduleReconnect();
    }
  }

  /// Update connection state and notify listeners
  void _updateConnectionState(ConvoyConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionController.add(newState);
      print('🔌 Connection state: $newState');
    }
  }

  /// Inspect how long the connection that just dropped lasted. A healthy
  /// connection (>[_shortLivedConnectionThreshold]) resets the short-lived
  /// counter. A connection that died quickly increments it — three of those
  /// in a row trips the circuit breaker in onDisconnect.
  void _recordConnectionLifetime() {
    final connectedAt = _connectedAt;
    _connectedAt = null;

    if (connectedAt == null) {
      // We dropped before ever connecting — count as a failure.
      _shortLivedConnections++;
      return;
    }

    final lifetime = DateTime.now().difference(connectedAt);
    if (lifetime >= _shortLivedConnectionThreshold) {
      // Healthy connection — reset.
      _shortLivedConnections = 0;
    } else {
      _shortLivedConnections++;
      print(
        '⚠️ Short-lived WebSocket connection ($lifetime, '
        '$_shortLivedConnections/$_maxShortLivedConnections)',
      );
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await disconnect();

    if (!_convoyController.isClosed) {
      await _convoyController.close();
    }

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    if (!_journeyEndedController.isClosed) {
      await _journeyEndedController.close();
    }

    if (!_participantArrivedController.isClosed) {
      await _participantArrivedController.close();
    }

    if (!_journeyStartedController.isClosed) {
      await _journeyStartedController.close();
    }

    if (!_participantAcceptedController.isClosed) {
      await _participantAcceptedController.close();
    }

    if (!_routeUpdatedController.isClosed) {
      await _routeUpdatedController.close();
    }

    if (!_journeyInviteController.isClosed) {
      await _journeyInviteController.close();
    }
  }
}
