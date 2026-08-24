import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tulink_flutter/core/auth/token_manager.dart';
import 'package:tulink_flutter/core/services/connectivity_service.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_remote_data_source.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_websocket_data_source.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/location_publish_ack.dart';
import 'package:tulink_flutter/features/convoy/data/models/location_update_dto.dart';
import 'package:tulink_flutter/features/convoy/data/services/location_outbox_service.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/journey_ended_event.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/participant_arrived_event.dart';

/// A socket the tests can hold open, answer out of order, and inspect.
class FakeConvoyWebSocketDataSource implements ConvoyWebSocketDataSource {
  final convoyUpdates = StreamController<ConvoySnapshot>.broadcast();
  final connectionStates = StreamController<ConvoyConnectionState>.broadcast();
  final journeyEnded = StreamController<JourneyEndedEvent>.broadcast();
  final participantArrived =
      StreamController<ParticipantArrivedEvent>.broadcast();
  final journeyStarted = StreamController<String>.broadcast();
  final participantAccepted = StreamController<String>.broadcast();
  final journeyInvite = StreamController<Map<String, dynamic>>.broadcast();

  /// Every room operation, in order, so a test can assert the handoff.
  final List<String> operations = [];

  /// Rooms whose `joinJourney` should hang until released.
  final Map<String, Completer<void>> joinGates = {};

  /// Rooms whose `joinJourney` should fail.
  final Set<String> joinFailures = {};

  String? joinedRoom;
  bool connected = false;
  bool throwOnPublish = false;
  LocationPublishAck nextAck = const LocationPublishAck.accepted();

  @override
  bool get isConnected => connected;

  @override
  ConvoyConnectionState get connectionState => connected
      ? ConvoyConnectionState.connected
      : ConvoyConnectionState.disconnected;

  @override
  Future<void> connect(String token) async {
    operations.add('connect');
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    operations.add('disconnect');
    connected = false;
    joinedRoom = null;
  }

  @override
  Future<void> reconnectIfDisconnected() async {}

  @override
  Future<void> joinJourney(String journeyId) async {
    operations.add('join:$journeyId');
    final gate = joinGates[journeyId];
    if (gate != null) await gate.future;
    if (joinFailures.contains(journeyId)) {
      operations.add('join-failed:$journeyId');
      throw StateError('join rejected for $journeyId');
    }
    operations.add('joined:$journeyId');
    joinedRoom = journeyId;
  }

  @override
  Future<void> leaveJourney(String journeyId) async {
    operations.add('leave:$journeyId');
    if (joinedRoom == journeyId) joinedRoom = null;
  }

  @override
  Future<LocationPublishAck> publishLocationUpdate(
    LocationUpdateDto locationUpdate,
  ) async {
    if (throwOnPublish) throw StateError('socket publish failed');
    return nextAck;
  }

  @override
  Stream<ConvoySnapshot> get convoyUpdatesStream => convoyUpdates.stream;

  @override
  Stream<ConvoyConnectionState> get connectionStateStream =>
      connectionStates.stream;

  @override
  Stream<JourneyEndedEvent> get journeyEndedStream => journeyEnded.stream;

  @override
  Stream<ParticipantArrivedEvent> get participantArrivedStream =>
      participantArrived.stream;

  @override
  Stream<String> get journeyStartedStream => journeyStarted.stream;

  @override
  Stream<String> get participantAcceptedStream => participantAccepted.stream;

  @override
  Stream<Map<String, dynamic>> get journeyInviteStream => journeyInvite.stream;

  @override
  Future<void> acknowledgeUpdate(int sequenceNumber) async {}

  @override
  Future<void> sendHeartbeat() async {}

  @override
  Future<void> requestResync(int fromSequence) async {}

  Future<void> close() async {
    await convoyUpdates.close();
    await connectionStates.close();
    await journeyEnded.close();
    await participantArrived.close();
    await journeyStarted.close();
    await participantAccepted.close();
    await journeyInvite.close();
  }
}

class FakeConvoyRemoteDataSource implements ConvoyRemoteDataSource {
  final List<LocationUpdateDto> published = [];
  bool deliver = true;
  Object? publishError;

  @override
  Future<bool> publishLocation(LocationUpdateDto locationUpdate) async {
    published.add(locationUpdate);
    final error = publishError;
    if (error != null) throw error;
    return deliver;
  }

  @override
  Future<Map<String, dynamic>> backfillLocations({
    required String journeyId,
    required String batchId,
    required List<Map<String, dynamic>> points,
  }) async => <String, dynamic>{
    'acknowledgedPointIds': <String>[],
    'rejected': <Map<String, dynamic>>[],
  };

  @override
  Future<ConvoySnapshot> fetchLatestSnapshot(String journeyId) async =>
      ConvoySnapshot(
        journeyId: journeyId,
        members: const {},
        destination: const ConvoyDestination(latitude: 0, longitude: 0),
        destinationAddress: 'nowhere',
      );
}

class FakeLocationOutboxService implements LocationOutboxService {
  final List<LocationUpdateDto> enqueued = [];
  final List<String> acknowledged = [];
  var _seq = 0;

  @override
  Future<LocationUpdateDto> enqueue(
    String userId,
    LocationUpdateDto point,
  ) async {
    final stored = LocationUpdateDto(
      journeyId: point.journeyId,
      location: point.location,
      timestamp: point.timestamp,
      clientPointId: point.clientPointId ?? 'p${++_seq}',
      accuracy: point.accuracy,
      altitude: point.altitude,
      heading: point.heading,
      speed: point.speed,
      metadata: point.metadata,
    );
    enqueued.add(stored);
    return stored;
  }

  @override
  Future<void> acknowledge(
    String userId,
    String journeyId,
    Iterable<String> pointIds,
  ) async => acknowledged.addAll(pointIds);

  @override
  List<LocationUpdateDto> pending(
    String userId,
    String journeyId, {
    int limit = 200,
  }) => const [];

  @override
  List<String> journeyIds(String userId) => const [];

  @override
  Future<void> markAttempt(
    String userId,
    String journeyId,
    Iterable<String> pointIds,
  ) async {}

  @override
  Future<void> quarantineRejected(
    String userId,
    String journeyId,
    Iterable<Map<String, dynamic>> rejected,
  ) async {}

  @override
  Map<String, dynamic> toBackfillPoint(LocationUpdateDto point) =>
      <String, dynamic>{};

  @override
  String batchIdFor(List<LocationUpdateDto> points) => 'batch';
}

class FakeTokenManager implements TokenManager {
  @override
  Future<String> getOrRefreshAuthToken() async => 'test-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnectivityService implements ConnectivityService {
  final _transitions = StreamController<bool>.broadcast();

  @override
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  @override
  Stream<bool> get transitions => _transitions.stream;

  @override
  Future<void> init() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
