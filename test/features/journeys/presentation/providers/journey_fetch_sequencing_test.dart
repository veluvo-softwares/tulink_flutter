import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';

import 'journey_provider_test.mocks.dart';

/// A fetch may install itself as the shared selection only while it is still
/// the newest request.
///
/// `fetchJourneyById` used to write `_currentJourney` for every successful
/// response with no sequencing at all, so a slow fetch for A landed after the
/// user had already switched to B and silently reinstated A — which is what
/// then let a `journey-started` transition activate the wrong journey.
void main() {
  Journey journey(String id, {JourneyStatus status = JourneyStatus.PENDING}) =>
      Journey(
        id: id,
        name: 'Trip $id',
        leaderId: 'leader-1',
        status: status,
        destination: const LatLng(latitude: -1.28, longitude: 36.82),
        destinationAddress: 'Nairobi',
        lagThresholdMeters: 500,
      );

  late MockJourneyRepository repository;
  late JourneyProvider provider;

  setUp(() {
    repository = MockJourneyRepository();
    provider = JourneyProvider(
      createJourneyUseCase: CreateJourney(repository),
      getJourneyByIdUseCase: GetJourneyById(repository),
      getActiveJourneysUseCase: GetActiveJourneys(repository),
      joinJourneyByCodeUseCase: JoinJourneyByCode(repository),
      startJourneyUseCase: StartJourney(repository),
      updateJourneyUseCase: UpdateJourney(repository),
      endJourneyUseCase: EndJourney(repository),
      switchActiveJourneyUseCase: SwitchActiveJourney(repository),
      cancelJourneyUseCase: CancelJourney(repository),
      leaveJourneyUseCase: LeaveJourney(repository),
    );
  });

  test('a slow A must not overwrite a selection that has moved to B', () async {
    final gateA = Completer<Result<Journey>>();
    when(repository.getJourneyById('A')).thenAnswer((_) => gateA.future);
    when(
      repository.getJourneyById('B'),
    ).thenAnswer((_) async => (data: journey('B'), failure: null));

    final a = provider.fetchJourneyById('A');
    await provider.fetchJourneyById('B');
    expect(provider.currentJourney?.id, 'B');

    gateA.complete((data: journey('A'), failure: null));
    final fetchedA = await a;

    expect(
      fetchedA?.id,
      'A',
      reason: "the caller still gets its own answer — it just isn't installed",
    );
    expect(
      provider.currentJourney?.id,
      'B',
      reason: 'a superseded fetch must not become the shared selection',
    );
  });

  test('an explicit selection outranks a fetch already in flight', () async {
    final gateA = Completer<Result<Journey>>();
    when(repository.getJourneyById('A')).thenAnswer((_) => gateA.future);

    final a = provider.fetchJourneyById('A');
    // The user picks B from history while A is still loading.
    provider.setCurrentJourney(journey('B'));

    gateA.complete((data: journey('A'), failure: null));
    await a;

    expect(provider.currentJourney?.id, 'B');
  });

  test('the selection generation moves only when identity changes', () async {
    when(
      repository.getJourneyById('A'),
    ).thenAnswer((_) async => (data: journey('A'), failure: null));

    final before = provider.selectionGeneration;
    await provider.fetchJourneyById('A');
    final afterFirst = provider.selectionGeneration;
    expect(afterFirst, greaterThan(before));

    // A roster refresh returns a fresh entity for the *same* journey. That is
    // not a selection change, and must not invalidate transitions legitimately
    // in flight for it.
    await provider.fetchJourneyById('A');
    expect(provider.selectionGeneration, afterFirst);

    when(
      repository.getJourneyById('B'),
    ).thenAnswer((_) async => (data: journey('B'), failure: null));
    await provider.fetchJourneyById('B');
    expect(provider.selectionGeneration, greaterThan(afterFirst));
  });

  test('releasing a finished journey moves the generation', () async {
    when(
      repository.getJourneyById('A'),
    ).thenAnswer((_) async => (data: journey('A'), failure: null));
    await provider.fetchJourneyById('A');
    final before = provider.selectionGeneration;

    provider.releaseFinishedJourney('A');

    expect(provider.currentJourney, isNull);
    expect(provider.selectionGeneration, greaterThan(before));
  });

  test(
    'a failed A leaves B selected and reports failure to its caller',
    () async {
      when(
        repository.getJourneyById('B'),
      ).thenAnswer((_) async => (data: journey('B'), failure: null));
      await provider.fetchJourneyById('B');

      when(repository.getJourneyById('A')).thenAnswer(
        (_) async => (
          data: null,
          failure: ServerFailure(message: 'boom', timestamp: DateTime.now()),
        ),
      );

      expect(await provider.fetchJourneyById('A'), isNull);
      expect(
        provider.currentJourney?.id,
        'B',
        reason: 'a failed fetch must not disturb the existing selection',
      );
    },
  );

  test('a response for a different journey is never adopted', () async {
    when(
      repository.getJourneyById('A'),
    ).thenAnswer((_) async => (data: journey('Z'), failure: null));

    expect(await provider.fetchJourneyById('A'), isNull);
    expect(provider.currentJourney, isNull);
    expect(provider.error, isNotNull);
  });

  test('a superseded fetch does not clear the newer loading flag', () async {
    final gateA = Completer<Result<Journey>>();
    final gateB = Completer<Result<Journey>>();
    when(repository.getJourneyById('A')).thenAnswer((_) => gateA.future);
    when(repository.getJourneyById('B')).thenAnswer((_) => gateB.future);

    unawaited(provider.fetchJourneyById('A'));
    unawaited(provider.fetchJourneyById('B'));

    gateA.complete((data: journey('A'), failure: null));
    await Future<void>.delayed(Duration.zero);

    expect(
      provider.isLoading,
      isTrue,
      reason: "A finishing must not report B's fetch as done",
    );

    gateB.complete((data: journey('B'), failure: null));
    await Future<void>.delayed(Duration.zero);
    expect(provider.isLoading, isFalse);
  });
}
