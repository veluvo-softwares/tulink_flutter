import 'dart:async';
import 'dart:math' as math;

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/member_position_model.dart';
import '../models/location_update_dto.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/journey_ended_event.dart';
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
  ConvoyConnectionState get connectionState => _connectionState;

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  Future<void> connect(String firebaseToken) async {
    if (isConnected) return;

    try {
      _intentionalDisconnect = false; // Reset flag when starting new connection
      // Fresh user-initiated connection — clear the short-lived counter so a
      // prior bad session doesn't immediately kill this one.
      _shortLivedConnections = 0;
      _updateConnectionState(ConvoyConnectionState.connecting);

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
    _socket!.emit('join-journey', {'journeyId': journeyId});
    
    print('🔌 Joining journey: $journeyId');
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

    _socket!.onDisconnect((_) {
      print('❌ WebSocket disconnected');
      _recordConnectionLifetime();

      if (_intentionalDisconnect) {
        print('🔌 Intentional disconnect - not attempting to reconnect');
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

    // Error events
    _socket!.onError((error) {
      print('❌ WebSocket error: $error');
      _updateConnectionState(ConvoyConnectionState.error);
    });

    // Journey lifecycle events
    _socket!.on('joined-journey', (data) {
      print('✅ Joined journey: ${data['journeyId']}');
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
      _handleLocationUpdate(data as Map<String, dynamic>);
    });

    _socket!.on('location-update-ack', (data) {
      final sequenceNumber = data['sequenceNumber'] as int?;
      print('✅ Location update acknowledged: $sequenceNumber');
    });

    _socket!.on('latest-locations', (data) {
      _handleLatestLocations(data as Map<String, dynamic>);
    });

    // Convoy alerts
    _socket!.on('lag-alert', (data) {
      final userId = data['userId'] as String?;
      final severity = data['severity'] as String?;
      print('⚠️ Lag alert for $userId: $severity');
      
      // Update member status if exists
      if (userId != null && _members.containsKey(userId)) {
        final member = _members[userId]!;
        _members[userId] = member.copyWith(statusChange: 'LAG');
        _emitConvoySnapshot();
      }
    });

    _socket!.on('arrival-detected', (data) {
      final userId = data['userId'] as String?;
      print('🎯 Arrival detected for: $userId');
      
      // Update member status if exists
      if (userId != null && _members.containsKey(userId)) {
        final member = _members[userId]!;
        _members[userId] = member.copyWith(statusChange: 'ARRIVED');
        _emitConvoySnapshot();
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

      // Convert WebSocket format to MemberPosition
      final memberData = {
        'userId': userId,
        'latitude': data['location']['latitude'],
        'longitude': data['location']['longitude'],
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
      final locations = data['locations'] as Map<String, dynamic>?;
      final destination = data['destination'] as Map<String, dynamic>?;
      final destinationAddress = data['destinationAddress'] as String?;

      // Clear and rebuild members map
      _members.clear();

      if (locations != null) {
        for (final entry in locations.entries) {
          final userId = entry.key;
          final locationData = entry.value as Map<String, dynamic>;
          
          try {
            final position = MemberPositionModel.fromJson({
              'userId': userId,
              ...locationData,
            });
            _members[userId] = position.toEntity();
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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
  }
}
