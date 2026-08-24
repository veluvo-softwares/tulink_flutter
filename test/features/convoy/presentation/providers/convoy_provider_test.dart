import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/stream_convoy_positions.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/publish_my_position.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/fetch_latest_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/repositories/convoy_repository.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/journey_ended_event.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/participant_arrived_event.dart';
import 'package:tulink_flutter/core/errors/failure.dart';

@GenerateMocks([
  StreamConvoyPositions,
  PublishMyPosition,
  FetchLatestSnapshot,
  ConvoyRepository,
])
import 'convoy_provider_test.mocks.dart';

void main() {
  group('ConvoyProvider - Self Filtering Tests', () {
    late ConvoyProvider convoyProvider;
    late MockStreamConvoyPositions mockStreamConvoyPositions;
    late MockPublishMyPosition mockPublishMyPosition;
    late MockFetchLatestSnapshot mockFetchLatestSnapshot;
    late MockConvoyRepository mockRepository;

    const currentUserId = 'user123';
    const otherUserId1 = 'user456';
    const otherUserId2 = 'user789';
    const journeyId = 'journey123';

    setUp(() {
      mockStreamConvoyPositions = MockStreamConvoyPositions();
      mockPublishMyPosition = MockPublishMyPosition();
      mockFetchLatestSnapshot = MockFetchLatestSnapshot();
      mockRepository = MockConvoyRepository();

      convoyProvider = ConvoyProvider(
        streamConvoyPositions: mockStreamConvoyPositions,
        publishMyPosition: mockPublishMyPosition,
        fetchLatestSnapshot: mockFetchLatestSnapshot,
        repository: mockRepository,
      );
    });

    group('getDisplaySnapshot', () {
      test('should exclude current user from display snapshot', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: false,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        // Set the snapshot directly for testing
        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final displaySnapshot = convoyProvider.getDisplaySnapshot(
          currentUserId,
        );

        // Assert
        expect(displaySnapshot, isNotNull);
        expect(displaySnapshot!.members.length, equals(2));
        expect(displaySnapshot.members.containsKey(currentUserId), isFalse);
        expect(displaySnapshot.members.containsKey(otherUserId1), isTrue);
        expect(displaySnapshot.members.containsKey(otherUserId2), isTrue);
      });

      test(
        'should return empty members map for solo journey with only current user',
        () {
          // Arrange
          final memberPositions = {
            currentUserId: MemberPosition(
              userId: currentUserId,
              latitude: 1.0,
              longitude: 1.0,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              accuracy: 5.0,
              isMoving: true,
            ),
          };

          final snapshot = ConvoySnapshot(
            journeyId: journeyId,
            members: memberPositions,
            destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
            destinationAddress: 'Test Destination',
            timestamp: DateTime.now(),
          );

          convoyProvider.setSnapshotForTesting(snapshot);

          // Act
          final displaySnapshot = convoyProvider.getDisplaySnapshot(
            currentUserId,
          );

          // Assert
          expect(displaySnapshot, isNotNull);
          expect(displaySnapshot!.members.length, equals(0));
          expect(displaySnapshot.members.containsKey(currentUserId), isFalse);
        },
      );

      test(
        'should return unchanged snapshot when current user not in members',
        () {
          // Arrange - Edge case: current user has not yet written to RTDB
          final memberPositions = {
            otherUserId1: MemberPosition(
              userId: otherUserId1,
              latitude: 2.0,
              longitude: 2.0,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              accuracy: 5.0,
              isMoving: true,
            ),
            otherUserId2: MemberPosition(
              userId: otherUserId2,
              latitude: 3.0,
              longitude: 3.0,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              accuracy: 5.0,
              isMoving: false,
            ),
          };

          final snapshot = ConvoySnapshot(
            journeyId: journeyId,
            members: memberPositions,
            destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
            destinationAddress: 'Test Destination',
            timestamp: DateTime.now(),
          );

          convoyProvider.setSnapshotForTesting(snapshot);

          // Act
          final displaySnapshot = convoyProvider.getDisplaySnapshot(
            currentUserId,
          );

          // Assert
          expect(displaySnapshot, isNotNull);
          expect(displaySnapshot!.members.length, equals(2));
          expect(displaySnapshot.members.containsKey(currentUserId), isFalse);
          expect(displaySnapshot.members.containsKey(otherUserId1), isTrue);
          expect(displaySnapshot.members.containsKey(otherUserId2), isTrue);
        },
      );

      test('should return null when no snapshot available', () {
        // Act
        final displaySnapshot = convoyProvider.getDisplaySnapshot(
          currentUserId,
        );

        // Assert
        expect(displaySnapshot, isNull);
      });
    });

    group('getFullSnapshot', () {
      test('should return unfiltered snapshot including current user', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final fullSnapshot = convoyProvider.getFullSnapshot();

        // Assert
        expect(fullSnapshot, isNotNull);
        expect(fullSnapshot!.members.length, equals(2));
        expect(fullSnapshot.members.containsKey(currentUserId), isTrue);
        expect(fullSnapshot.members.containsKey(otherUserId1), isTrue);
      });
    });

    group('joinJourneyRoom', () {
      void stubEventStreams() {
        when(
          mockRepository.connectionStateStream,
        ).thenAnswer((_) => const Stream<ConvoyConnectionState>.empty());
        when(
          mockRepository.journeyEndedStream,
        ).thenAnswer((_) => const Stream.empty());
        when(
          mockRepository.participantArrivedStream,
        ).thenAnswer((_) => const Stream.empty());
        when(
          mockRepository.journeyStartedStream,
        ).thenAnswer((_) => const Stream<String>.empty());
        when(
          mockRepository.participantAcceptedStream,
        ).thenAnswer((_) => const Stream<String>.empty());
        when(
          mockStreamConvoyPositions(journeyId),
        ).thenAnswer((_) => const Stream.empty());
      }

      test(
        'waits for the server room acknowledgement before subscribing',
        () async {
          stubEventStreams();
          when(
            mockRepository.joinJourneyRoom(journeyId),
          ).thenAnswer((_) async {});

          final joined = await convoyProvider.joinJourneyRoom(journeyId);

          expect(joined, isTrue);
          expect(convoyProvider.errorMessage, isNull);
          verifyInOrder([
            mockRepository.joinJourneyRoom(journeyId),
            mockStreamConvoyPositions(journeyId),
          ]);
        },
      );

      test(
        'reports reconnecting and does not subscribe when acknowledgement fails',
        () async {
          when(mockRepository.joinJourneyRoom(journeyId)).thenThrow(
            const ConvoyFailure(
              message: 'Join acknowledgement timed out',
              isRetryable: true,
            ),
          );

          final joined = await convoyProvider.joinJourneyRoom(journeyId);

          expect(joined, isFalse);
          expect(convoyProvider.errorMessage, 'Live updates are reconnecting');
          verifyNever(mockStreamConvoyPositions(journeyId));
        },
      );

      test(
        'same-room no-op keeps the installed event listeners live',
        () async {
          final started = StreamController<String>.broadcast();
          addTearDown(started.close);
          stubEventStreams();
          when(
            mockRepository.journeyStartedStream,
          ).thenAnswer((_) => started.stream);
          when(
            mockRepository.joinJourneyRoom(journeyId),
          ).thenAnswer((_) async {});

          expect(await convoyProvider.joinJourneyRoom(journeyId), isTrue);
          expect(await convoyProvider.joinJourneyRoom(journeyId), isTrue);

          started.add(journeyId);
          await Future<void>.delayed(Duration.zero);

          expect(convoyProvider.pendingJourneyStartedId, journeyId);
          verify(mockRepository.joinJourneyRoom(journeyId)).called(1);
          verify(mockStreamConvoyPositions(journeyId)).called(1);
        },
      );

      test(
        'room B is installed only after captured room A cancellation settles',
        () async {
          final cancelGate = Completer<void>();
          final streamedJourneys = <String>[];
          final snapshotsA =
              StreamController<
                ({ConvoySnapshot? snapshot, Failure? failure})
              >.broadcast(onCancel: () => cancelGate.future);
          final snapshotsB =
              StreamController<
                ({ConvoySnapshot? snapshot, Failure? failure})
              >.broadcast();
          final started = StreamController<String>.broadcast();
          final ended = StreamController<JourneyEndedEvent>.broadcast();
          final arrived = StreamController<ParticipantArrivedEvent>.broadcast();
          addTearDown(() async {
            if (!cancelGate.isCompleted) cancelGate.complete();
            await snapshotsA.close();
            await snapshotsB.close();
            await started.close();
            await ended.close();
            await arrived.close();
          });

          when(
            mockRepository.connectionStateStream,
          ).thenAnswer((_) => const Stream<ConvoyConnectionState>.empty());
          when(
            mockRepository.journeyEndedStream,
          ).thenAnswer((_) => ended.stream);
          when(
            mockRepository.participantArrivedStream,
          ).thenAnswer((_) => arrived.stream);
          when(
            mockRepository.journeyStartedStream,
          ).thenAnswer((_) => started.stream);
          when(
            mockRepository.participantAcceptedStream,
          ).thenAnswer((_) => const Stream<String>.empty());
          when(mockRepository.joinJourneyRoom(any)).thenAnswer((_) async {});
          when(mockRepository.stopCoordination()).thenAnswer((_) async {});
          when(mockStreamConvoyPositions(any)).thenAnswer((invocation) {
            final id = invocation.positionalArguments.single as String;
            streamedJourneys.add(id);
            return id == 'A'
                ? _GatedCancelStream(snapshotsA.stream, cancelGate)
                : snapshotsB.stream;
          });

          expect(await convoyProvider.joinJourneyRoom('A'), isTrue);
          final switching = convoyProvider.joinJourneyRoom('B');
          await Future<void>.delayed(Duration.zero);

          expect(streamedJourneys, ['A']);
          cancelGate.complete();
          expect(await switching, isTrue);
          expect(streamedJourneys, ['A', 'B']);

          started.add('A');
          arrived.add(
            ParticipantArrivedEvent(
              userId: 'stale-A',
              arrivedCount: 1,
              totalCount: 2,
              allArrived: false,
              timestamp: DateTime.utc(2026),
            ),
          );
          ended.add(const JourneyEndedEvent(journeyId: 'A'));
          await Future<void>.delayed(Duration.zero);
          expect(convoyProvider.currentJourneyId, 'B');
          expect(convoyProvider.pendingJourneyStartedId, isNull);
          expect(convoyProvider.lastJourneyEndedEvent, isNull);

          started.add('B');
          arrived.add(
            ParticipantArrivedEvent(
              userId: 'member-B',
              arrivedCount: 1,
              totalCount: 3,
              allArrived: false,
              timestamp: DateTime.utc(2026),
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(convoyProvider.pendingJourneyStartedId, 'B');
          expect(convoyProvider.arrivedCount, 1);
          expect(convoyProvider.totalMemberCount, 3);
        },
      );

      test(
        'duplicate journey-ended events reconcile the owned room once',
        () async {
          final ended = StreamController<JourneyEndedEvent>.broadcast(
            sync: true,
          );
          addTearDown(ended.close);
          stubEventStreams();
          when(
            mockRepository.journeyEndedStream,
          ).thenAnswer((_) => ended.stream);
          when(
            mockRepository.joinJourneyRoom(journeyId),
          ).thenAnswer((_) async {});
          when(mockRepository.stopCoordination()).thenAnswer((_) async {});
          await convoyProvider.joinJourneyRoom(journeyId);

          ended
            ..add(
              const JourneyEndedEvent(journeyId: journeyId, reason: 'first'),
            )
            ..add(
              const JourneyEndedEvent(
                journeyId: journeyId,
                reason: 'duplicate',
              ),
            );
          await Future<void>.delayed(Duration.zero);

          expect(convoyProvider.lastJourneyEndedEvent?.reason, 'first');
          expect(convoyProvider.currentJourneyId, isNull);
          verify(mockRepository.stopCoordination()).called(1);
        },
      );
    });

    group('Member count consistency', () {
      test('display snapshot should have fewer members than full snapshot', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: false,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final fullSnapshot = convoyProvider.getFullSnapshot();
        final displaySnapshot = convoyProvider.getDisplaySnapshot(
          currentUserId,
        );

        // Assert
        expect(fullSnapshot!.totalMembers, equals(3));
        expect(displaySnapshot!.totalMembers, equals(2));
        expect(
          fullSnapshot.totalMembers - displaySnapshot.totalMembers,
          equals(1),
        );
      });
    });
  });
}

class _GatedCancelStream<T> extends Stream<T> {
  const _GatedCancelStream(this._delegate, this._cancelGate);

  final Stream<T> _delegate;
  final Completer<void> _cancelGate;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _GatedCancelSubscription<T>(
    _delegate.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
    _cancelGate,
  );
}

class _GatedCancelSubscription<T> implements StreamSubscription<T> {
  const _GatedCancelSubscription(this._delegate, this._cancelGate);

  final StreamSubscription<T> _delegate;
  final Completer<void> _cancelGate;

  @override
  Future<void> cancel() async {
    await _delegate.cancel();
    await _cancelGate.future;
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture(futureValue);
}

// Test helper method is now available directly on ConvoyProvider as setSnapshotForTesting()
