import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/member_position_model.dart';
import '../models/location_update_dto.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
import '../../domain/entities/participant_arrived_event.dart';
import '../../domain/entities/member_position.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failure.dart';

/// Abstract interface for convoy WebSocket operations
abstract class ConvoyWebSocketDataSource {
  /// Connect to convoy coordination WebSocket
  Future<void> connect(String firebaseToken);

  /// Disconnect from WebSocket
  Future<void> disconnect();

  /// Join a journey room for real-time updates
  Future<void> joinJourney(String journeyId);

  /// Leave a journey room
  Future<void> leaveJourney(String journeyId);

  /// Publish location update via WebSocket
  Future<void> publishLocationUpdate(LocationUpdateDto locationUpdate);

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
  /// accepts; emits the current journeyId so the leader can refresh its
  /// participant list live without a manual reload.
  Stream<String> get participantAcceptedStream;

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
  ConvoyWebSocketDataSourceImpl();

  io.Socket? _socket;
  String? _currentJourneyId;
  ConvoyConnectionState _connectionState = ConvoyConnectionState.disconnected;
  
  // Stream controllers
  final StreamController<ConvoySnapshot> _convoyController = StreamController.broadcast();
  final StreamController<ConvoyConnectionState> _connectionController = StreamController.broadcast();
  final StreamController<JourneyEndedEvent> _journeyEndedController = StreamController.broadcast();
  final StreamController<ParticipantArrivedEvent> _participantArrivedController = StreamController.broadcast();
  final StreamController<String> _journeyStartedController = StreamController.broadcast();
  final StreamController<String> _participantAcceptedController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _journeyInviteController = StreamController.broadcast();
  
  // Convoy state
  final Map<String, MemberPosition> _members = {};
  ConvoyDestination? _destination;
  String? _destinationAddress;
  
  // Connection management
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false; // Flag to prevent reconnection on intentional disconnect
  static const int _maxReconnectAttempts = 10;
  static const List<int> _reconnectDelays = [1, 2, 4, 8, 15, 30]; // seconds

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
  static const int _maxShortLivedConnections = 3;
  static const Duration _shortLivedConnectionThreshold = Duration(seconds: 20);

  @override
  Stream<ConvoySnapshot> get convoyUpdatesStream => _convoyController.stream;

  @override
  Stream<ConvoyConnectionState> get connectionStateStream => _connectionController.stream;

  @override
  Stream<JourneyEndedEvent> get journeyEndedStream => _journeyEndedController.stream;

  @override
  Stream<ParticipantArrivedEvent> get participantArrivedStream =>
      _participantArrivedController.stream;

  @override
  Stream<String> get journeyStartedStream => _journeyStartedController.stream;

  @override
  Stream<String> get participantAcceptedStream =>
      _participantAcceptedController.stream;

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
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setAuth({'token': firebaseToken})
            .build(),
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

    _currentJourneyId = journeyId;

    // Await joined-journey confirmation so we know whether the server actually
    // added us to the room (vs silently rejecting with an error event).
    final completer = Completer<void>();

    late void Function(dynamic) onJoined;
    onJoined = (data) {
      _socket!.off('joined-journey', onJoined);
      _roomDebug('✅ joined-journey ACK for $journeyId');
      if (!completer.isCompleted) completer.complete();
    };

    _socket!.on('joined-journey', onJoined);
    _socket!.emit('join-journey', {'journeyId': journeyId});

    _roomDebug('🔌 emit join-journey $journeyId');

    // 10-second timeout — if joined-journey never arrives (e.g. server rejected
    // with an error event), log a warning and continue so a slow server doesn't
    // block coordination indefinitely. The caller will surface the failure via
    // missing snapshots and eventually fall back to REST polling.
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _socket!.off('joined-journey', onJoined);
        print('⚠️ join-journey timed out for $journeyId — server may have rejected membership');
      },
    );
  }

  @override
  Future<void> leaveJourney(String journeyId) async {
    if (!isConnected || _currentJourneyId != journeyId) return;

    _socket!.emit('leave-journey', {'journeyId': journeyId});
    _currentJourneyId = null;
    
    // Clear convoy state
    _members.clear();
    _destination = null;
    _destinationAddress = null;
    
    print('🔌 Left journey: $journeyId');
  }

  @override
  Future<void> publishLocationUpdate(LocationUpdateDto locationUpdate) async {
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
      if (locationUpdate.accuracy != null) 'accuracy': locationUpdate.accuracy,
      if (locationUpdate.altitude != null) 'altitude': locationUpdate.altitude,
      if (locationUpdate.heading != null) 'heading': locationUpdate.heading,
      if (locationUpdate.speed != null) 'speed': locationUpdate.speed,
      if (locationUpdate.metadata != null) 'metadata': locationUpdate.metadata,
    };

    _socket!.emit('location-update', payload);
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
    
    _socket!.emit('request-resync', {'fromSequence': fromSequence});
  }

  /// Setup event listeners for WebSocket
  void _setupEventListeners() {
    if (_socket == null) return;

    // Connection events
    _socket!.onConnect((_) {
      print('✅ WebSocket connected');
      _connectedAt = DateTime.now();
      _updateConnectionState(ConvoyConnectionState.connected);
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
      if (reasonStr.contains('server disconnect')) {
        print('🔌 Server-initiated disconnect ($reasonStr) - not reconnecting');
        _intentionalDisconnect = true;
        _stopReconnectTimer();
        _updateConnectionState(ConvoyConnectionState.disconnected);
        return;
      }

      // Give up if too many recent connections died in their crib — this is
      // the connect→heartbeat-timeout→reconnect loop. The regular attempt
      // counter doesn't catch it because the TCP handshake itself succeeds.
      if (_shortLivedConnections >= _maxShortLivedConnections) {
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
      // Emit an empty snapshot immediately so the provider has a non-null
      // snapshot to work with while waiting for latest-locations.
      _emitConvoySnapshot();
    });

    _socket!.on('left-journey', (data) {
      print('✅ Left journey: ${data['journeyId']}');
    });

    _socket!.on('journey-ended', (data) {
      print('🏁 Journey ended: $data');

      // Notify listeners so ConvoyProvider can stop publishing and surface UI.
      // The journeyId we care about is whichever one we're currently in —
      // the backend emits this event to that journey's room only.
      final journeyId = _currentJourneyId;
      if (journeyId != null) {
        final payload = data is Map<String, dynamic> ? data : <String, dynamic>{};
        if (!_journeyEndedController.isClosed) {
          _journeyEndedController.add(
            JourneyEndedEvent.fromJson(journeyId, payload),
          );
        }
      }

      // Server will close the socket immediately after — treat that close as
      // intentional so we don't kick off the reconnect loop.
      _intentionalDisconnect = true;

      // Clear convoy state and notify listeners
      _members.clear();
      _emitConvoySnapshot();
    });

    _socket!.on('journey-started', (data) {
      _roomDebug(
          '🚀 journey-started RECV currentJourney=$_currentJourneyId data=$data');
      final journeyId = _currentJourneyId;
      if (journeyId != null && !_journeyStartedController.isClosed) {
        _journeyStartedController.add(journeyId);
      } else {
        _roomDebug('⚠️ journey-started DROPPED (currentJourneyId=$journeyId)');
      }
    });

    _socket!.on('participant-accepted', (data) {
      final userId = data is Map ? data['userId'] : null;
      _roomDebug(
          '🤝 participant-accepted RECV userId=$userId currentJourney=$_currentJourneyId');
      final journeyId = _currentJourneyId;
      if (journeyId != null && !_participantAcceptedController.isClosed) {
        _participantAcceptedController.add(journeyId);
      } else {
        _roomDebug(
            '⚠️ participant-accepted DROPPED (currentJourneyId=$journeyId)');
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
            timestamp: DateTime.now().millisecondsSinceEpoch - 60000, // Mark as 1 min old
          );
          _emitConvoySnapshot();
        }
      }
      print('🔌 Participant disconnected: $userId');
    });

    // Location update events
    _socket!.on('location-update', (data) {
      if (data is! Map) return;
      _handleLocationUpdate(data.cast<String, dynamic>());
    });

    _socket!.on('location-update-ack', (data) {
      final sequenceNumber = data['sequenceNumber'] as int?;
      print('✅ Location update acknowledged: $sequenceNumber');
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
      final count = data['count'] as int?;
      print('🔄 Resync data received: $count updates');
      
      // TODO: Handle resync updates if needed
      // final updates = data['updates'] as List<dynamic>?;
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
      _members[userId] = position.toEntity();
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
            final memberId =
                locationData['userId'] as String? ?? userId;

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
            }).toEntity();

            // Upsert: never let an older snapshot position overwrite a fresher
            // one we already have from a live update.
            final existing = _members[memberId];
            if (existing == null ||
                position.timestamp >= existing.timestamp) {
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

  /// Emit convoy snapshot to listeners
  void _emitConvoySnapshot() {
    if (_currentJourneyId == null) return;

    final snapshot = ConvoySnapshot(
      journeyId: _currentJourneyId!,
      members: Map.from(_members),
      destination: _destination ?? const ConvoyDestination(latitude: 0, longitude: 0),
      destinationAddress: _destinationAddress ?? 'Unknown destination',
      timestamp: DateTime.now(),
    );

    _convoyController.add(snapshot);
  }

  /// Wait for WebSocket connection with timeout
  Future<void> _waitForConnection() async {
    const timeout = Duration(seconds: 10);
    final completer = Completer<void>();
    
    Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError('Connection timeout');
      }
    });

    // Setup one-time listeners for connection
    _socket!.on('connect', (_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    _socket!.on('connect_error', (error) {
      if (!completer.isCompleted) {
        completer.completeError(error as Object);
      }
    });

    await completer.future;
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
  void _scheduleReconnect() {
    if (_intentionalDisconnect) {
      print('🔌 Skipping reconnect - intentional disconnect');
      return;
    }
    
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _updateConnectionState(ConvoyConnectionState.error);
      return;
    }

    _stopReconnectTimer();
    
    final delayIndex = math.min(_reconnectAttempts, _reconnectDelays.length - 1);
    final delay = Duration(seconds: _reconnectDelays[delayIndex]);
    
    print('🔄 Scheduling reconnect attempt ${_reconnectAttempts + 1} in ${delay.inSeconds}s');
    
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

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (isConnected || _intentionalDisconnect) return;

    try {
      print('🔄 Attempting reconnect...');
      _updateConnectionState(ConvoyConnectionState.reconnecting);
      
      // Try to reconnect
      _socket?.connect();
      await _waitForConnection();
      
      // Rejoin journey if we were in one
      if (_currentJourneyId != null) {
        await joinJourney(_currentJourneyId!);
      }
      
      _reconnectAttempts = 0;
    } catch (e) {
      print('❌ Reconnect failed: $e');
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

    if (!_journeyInviteController.isClosed) {
      await _journeyInviteController.close();
    }
  }
}
