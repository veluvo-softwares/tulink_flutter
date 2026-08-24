import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/location_publish_ack.dart';
import 'package:tulink_flutter/features/convoy/data/models/location_update_dto.dart';
import 'package:tulink_flutter/features/convoy/data/repositories/convoy_repository_impl.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';

import '_convoy_test_doubles.dart';

/// What the repository does with each WebSocket publish answer.
///
/// The shipped behaviour: the data source logged `accepted` and completed the
/// emit as success regardless, so the repository removed the point from the
/// offline outbox and never used the REST fallback. A negative ack therefore
/// destroyed the point — silently.
void main() {
  late FakeConvoyWebSocketDataSource ws;
  late FakeConvoyRemoteDataSource rest;
  late FakeLocationOutboxService outbox;
  late ConvoyRepositoryImpl repository;

  LocationUpdateDto point(String id) => LocationUpdateDto(
    journeyId: 'j1',
    location: const LocationCoordinatesDto(latitude: -1.29, longitude: 36.82),
    timestamp: 1000,
    clientPointId: id,
  );

  Future<void> connect() async {
    await repository.joinJourneyRoom('j1');
    ws.connectionStates.add(ConvoyConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
  }

  Future<({bool success, Failure? failure})> publish() =>
      repository.publishMyPosition(
        journeyId: 'j1',
        latitude: -1.29,
        longitude: 36.82,
        timestamp: 1000,
      );

  setUp(() {
    ws = FakeConvoyWebSocketDataSource();
    rest = FakeConvoyRemoteDataSource();
    outbox = FakeLocationOutboxService();
    repository = ConvoyRepositoryImpl(
      remoteDataSource: rest,
      webSocketDataSource: ws,
      tokenManager: FakeTokenManager(),
      outboxService: outbox,
      connectivityService: FakeConnectivityService(),
      currentUserId: () async => 'u1',
    );
  });

  tearDown(() async {
    await repository.dispose();
  });

  test('an accepted point is removed from the outbox', () async {
    await connect();
    ws.nextAck = const LocationPublishAck.accepted(sequenceNumber: 1);

    final result = await publish();

    expect(result.success, isTrue);
    expect(result.failure, isNull);
    expect(outbox.acknowledged, hasLength(1));
    expect(rest.published, isEmpty, reason: 'no REST fallback was needed');
  });

  test('a throttled/duplicate point is delivered, not resent', () async {
    await connect();
    ws.nextAck = const LocationPublishAck(
      outcome: LocationAckOutcome.suppressed,
      reason: 'THROTTLED_OR_DUPLICATE',
    );

    final result = await publish();

    expect(result.success, isTrue);
    expect(
      outbox.acknowledged,
      hasLength(1),
      reason: 'the server has the point, or intentionally dropped it',
    );
    expect(
      rest.published,
      isEmpty,
      reason: 'resending would just lose the same dedup race again',
    );
  });

  test('SERVER_ERROR keeps the point and uses the REST fallback', () async {
    // The regression this whole finding is about.
    await connect();
    ws.nextAck = const LocationPublishAck(
      outcome: LocationAckOutcome.retryable,
      reason: 'SERVER_ERROR',
    );
    rest.deliver = true;

    final result = await publish();

    expect(
      rest.published,
      hasLength(1),
      reason: 'a rejected WebSocket publish must fall back to REST',
    );
    expect(result.success, isTrue);
    expect(outbox.acknowledged, hasLength(1), reason: 'REST delivered it');
  });

  test('SERVER_ERROR with a failed REST fallback retains the point', () async {
    await connect();
    ws.nextAck = const LocationPublishAck(
      outcome: LocationAckOutcome.retryable,
      reason: 'SERVER_ERROR',
    );
    rest.deliver = false;

    final result = await publish();

    expect(
      outbox.acknowledged,
      isEmpty,
      reason: 'an undelivered point must stay queued for backfill',
    );
    expect(
      result.failure,
      isNotNull,
      reason: 'degraded delivery must be reported, not dressed up as success',
    );
  });

  test('a timed-out ack is not a delivery', () async {
    await connect();
    ws.nextAck = LocationPublishAck.timedOut;
    rest.deliver = false;

    await publish();

    expect(rest.published, hasLength(1), reason: 'REST fallback still runs');
    expect(outbox.acknowledged, isEmpty);
  });

  test('a malformed ack is not a delivery', () async {
    await connect();
    ws.nextAck = LocationPublishAck.malformed;
    rest.deliver = false;

    await publish();

    expect(outbox.acknowledged, isEmpty);
  });

  test('a terminal rejection surfaces a typed failure and stops', () async {
    await connect();
    ws.nextAck = const LocationPublishAck(
      outcome: LocationAckOutcome.terminal,
      reason: 'NOT_PARTICIPANT',
    );

    final result = await publish();

    expect(result.success, isFalse);
    expect(
      result.failure,
      ConvoyFailure.notJourneyMember,
      reason: 'the provider already treats this as stop-publishing',
    );
    expect(
      rest.published,
      isEmpty,
      reason: 'REST cannot succeed where the socket was refused for membership',
    );
    expect(
      outbox.acknowledged,
      hasLength(1),
      reason:
          'a payload the server will never accept must not block every later '
          'point behind it forever',
    );
  });

  test('JOURNEY_NOT_ACTIVE maps to its own typed failure', () async {
    await connect();
    ws.nextAck = const LocationPublishAck(
      outcome: LocationAckOutcome.terminal,
      reason: 'JOURNEY_NOT_ACTIVE',
    );

    final result = await publish();
    expect(result.failure, ConvoyFailure.journeyNotActive);
  });

  test('a thrown WebSocket publish still falls back to REST', () async {
    await connect();
    ws.throwOnPublish = true;
    rest.deliver = true;

    final result = await publish();

    expect(rest.published, hasLength(1));
    expect(result.success, isTrue);
    expect(outbox.acknowledged, hasLength(1));
  });

  test('every point is queued before any transport is attempted', () async {
    await connect();
    ws.nextAck = const LocationPublishAck.accepted();

    await publish();

    expect(
      outbox.enqueued,
      hasLength(1),
      reason: 'the outbox is the durability guarantee, not the transport',
    );
    expect(outbox.enqueued.single.clientPointId, isNotNull);
    expect(point('x').clientPointId, 'x');
  });
}
