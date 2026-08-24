import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/repositories/convoy_repository_impl.dart';

import '_convoy_test_doubles.dart';

/// A user is in at most one convoy room, and exactly one attempt owns it.
///
/// The shipped code claimed its generation token in the provider *after* the
/// already-joined shortcut, so two joins started before `_currentJourneyId` or
/// `_isSubscribed` was assigned both reached the repository. The repository then
/// wrote its journey id *before* awaiting the connection and the server ack, so
/// A and B interleaved and whichever ack landed last decided which room the
/// client believed it was in.
///
/// There are two distinct ways a newer B can supersede A, and both are pinned
/// here: B arriving while A is still **queued**, and B arriving while A is
/// already **waiting on the server**.
void main() {
  late FakeConvoyWebSocketDataSource ws;
  late ConvoyRepositoryImpl repository;

  /// Attach a handler immediately: a superseded attempt rejects, and an
  /// unhandled async error would fail the test for the wrong reason.
  Future<Object?> attempt(String journeyId) => repository
      .joinJourneyRoom(journeyId)
      .then<Object?>((_) => null, onError: (Object error) => error);

  /// Let the queue drain far enough for an attempt to reach `joinJourney`.
  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    ws = FakeConvoyWebSocketDataSource();
    repository = ConvoyRepositoryImpl(
      remoteDataSource: FakeConvoyRemoteDataSource(),
      webSocketDataSource: ws,
      tokenManager: FakeTokenManager(),
      outboxService: FakeLocationOutboxService(),
      connectivityService: FakeConnectivityService(),
      currentUserId: () async => 'u1',
    );
  });

  tearDown(() async {
    await repository.dispose();
    await ws.close();
  });

  test('B issued while A is queued: A never touches the transport', () async {
    final a = attempt('A');
    final b = attempt('B');

    expect(await a, isA<StaleRoomAttempt>());
    expect(await b, isNull);

    expect(
      ws.operations.where((op) => op.startsWith('join:')),
      ['join:B'],
      reason: 'a superseded attempt must not emit a join at all',
    );
    expect(ws.joinedRoom, 'B');
  });

  test(
    'B issued while A awaits the server: A joins, then gives it back',
    () async {
      final gateA = Completer<void>();
      ws.joinGates['A'] = gateA;

      final a = attempt('A');
      await settle();
      expect(ws.operations, contains('join:A'));

      // B arrives while the server is still deciding about A.
      final b = attempt('B');
      gateA.complete();

      expect(await a, isA<StaleRoomAttempt>());
      expect(await b, isNull);

      // A really was in the server room, and really left it.
      expect(ws.operations, contains('joined:A'));
      expect(
        ws.operations.indexOf('leave:A'),
        greaterThan(ws.operations.indexOf('joined:A')),
        reason: 'a stale server room must be left, not abandoned',
      );
      expect(
        ws.joinedRoom,
        'B',
        reason: 'the newest validated attempt owns the room',
      );
    },
  );

  test('B finishing first is not undone by A finishing late', () async {
    final gateA = Completer<void>();
    ws.joinGates['A'] = gateA;

    final a = attempt('A');
    await settle();
    final b = attempt('B');
    gateA.complete();
    await b;

    expect(ws.joinedRoom, 'B');
    expect(await a, isA<StaleRoomAttempt>());
    expect(
      ws.joinedRoom,
      'B',
      reason: "A's late completion must not steal the room from B",
    );
  });

  test('a failed B join leaves a deterministic, recoverable state', () async {
    expect(await attempt('A'), isNull);
    expect(ws.joinedRoom, 'A');

    ws.joinFailures.add('B');
    expect(await attempt('B'), isA<StateError>());

    // Not a mixed A/B state: A has been released and B was never adopted.
    expect(ws.joinedRoom, isNull);
    expect(ws.operations, contains('leave:A'));

    // And it is recoverable by simply retrying.
    ws.joinFailures.remove('B');
    expect(await attempt('B'), isNull);
    expect(ws.joinedRoom, 'B');
  });

  test('stopping releases the room and invalidates a pending join', () async {
    final gateA = Completer<void>();
    ws.joinGates['A'] = gateA;

    final a = attempt('A');
    await settle();
    final stop = repository.stopCoordination();
    gateA.complete();

    expect(await a, isA<StaleRoomAttempt>());
    await stop;

    expect(ws.joinedRoom, isNull);
  });

  test('rejoining the room already held is a no-op', () async {
    await attempt('A');
    final before = List<String>.from(ws.operations);

    await attempt('A');

    expect(
      ws.operations,
      before,
      reason: 'a redundant join must not churn a healthy room',
    );
  });

  test('going live in B releases the listener room A first', () async {
    await attempt('A');
    expect(ws.joinedRoom, 'A');

    // Upgrading to full coordination for a *different* journey.
    repository.streamConvoyPositions('B');
    await settle();

    expect(ws.operations, contains('leave:A'));
    expect(ws.joinedRoom, 'B');
  });
}
