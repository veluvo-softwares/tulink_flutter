import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/repositories/journey_repository.dart';
import 'package:tulink_flutter/features/journeys/domain/usecases/journey_usecases.dart';
import 'package:tulink_flutter/features/journeys/presentation/providers/journey_provider.dart';

@GenerateMocks([JourneyRepository])
import 'journey_provider_test.mocks.dart';

void main() {
  const pendingJourney = Journey(
    id: 'journey-pending',
    name: 'Weekend convoy',
    leaderId: 'leader-1',
    status: JourneyStatus.PENDING,
    destination: LatLng(latitude: -1.28, longitude: 36.82),
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
      getCachedActiveJourneysUseCase: GetCachedActiveJourneys(repository),
    );
    // Default: nothing cached, so tests that do not care about hydration
    // behave exactly as they did before.
    when(repository.getCachedActiveJourneys()).thenAnswer((_) async => const []);
  });

  test(
    'server pending journey becomes current without a manual refresh',
    () async {
      when(
        repository.getActiveJourneys(),
      ).thenAnswer((_) async => (data: [pendingJourney], failure: null));

      await provider.fetchActiveJourneys();

      expect(provider.currentJourney, pendingJourney);
      expect(provider.activeJourneys, [pendingJourney]);
    },
  );

  group('painting from cache before the network answers', () {
    test('cached journeys are shown without waiting for the fetch', () async {
      when(
        repository.getCachedActiveJourneys(),
      ).thenAnswer((_) async => [pendingJourney]);
      // A fetch that never resolves stands in for a slow cold start.
      when(
        repository.getActiveJourneys(),
      ).thenAnswer((_) => Completer<Result<List<Journey>>>().future);

      unawaited(provider.fetchActiveJourneys());
      await Future<void>.delayed(Duration.zero);

      expect(provider.activeJourneys, [pendingJourney]);
      expect(provider.currentJourney, pendingJourney);
    });

    test('the server answer replaces what the cache painted', () async {
      const serverJourney = Journey(
        id: 'journey-from-server',
        name: 'Server convoy',
        leaderId: 'leader-1',
        status: JourneyStatus.ACTIVE,
        destination: LatLng(latitude: -1.28, longitude: 36.82),
        destinationAddress: 'Nairobi',
        lagThresholdMeters: 500,
      );
      when(
        repository.getCachedActiveJourneys(),
      ).thenAnswer((_) async => [pendingJourney]);
      when(
        repository.getActiveJourneys(),
      ).thenAnswer((_) async => (data: [serverJourney], failure: null));

      await provider.fetchActiveJourneys();

      expect(provider.activeJourneys, [serverJourney]);
    });

    test('a stale cache cannot retire a live journey', () async {
      // Reconciliation clears currentJourney when the server stops listing it.
      // That is only meaningful against a server-authoritative answer — running
      // it over cached data would let an out-of-date cache cancel a journey
      // that is actually still running.
      when(
        repository.getCachedActiveJourneys(),
      ).thenAnswer((_) async => const []);
      when(
        repository.getActiveJourneys(),
      ).thenAnswer((_) async => (data: [pendingJourney], failure: null));

      await provider.fetchActiveJourneys();
      expect(provider.currentJourney, pendingJourney);

      // A second pass whose cache is empty must leave the journey alone until
      // the server itself says otherwise.
      when(
        repository.getActiveJourneys(),
      ).thenAnswer((_) => Completer<Result<List<Journey>>>().future);

      unawaited(provider.fetchActiveJourneys());
      await Future<void>.delayed(Duration.zero);

      expect(provider.currentJourney, pendingJourney);
    });
  });

  test(
    'joining with a code promotes the journey into local open state',
    () async {
      when(
        repository.joinJourneyByCode('ABCD234567'),
      ).thenAnswer((_) async => (data: pendingJourney, failure: null));

      final joined = await provider.joinJourneyByCode('ABCD234567');

      expect(joined, pendingJourney);
      expect(provider.currentJourney, pendingJourney);
      expect(provider.activeJourneys, [pendingJourney]);
    },
  );

  test(
    'cancelling the current pending journey clears local open state',
    () async {
      provider.setCurrentJourney(pendingJourney);
      when(
        repository.cancelJourney(pendingJourney.id),
      ).thenAnswer((_) async => (data: true, failure: null));

      final cancelled = await provider.cancelJourney(pendingJourney.id);

      expect(cancelled, isTrue);
      expect(provider.currentJourney, isNull);
      expect(provider.activeJourneys, isEmpty);
    },
  );
}
