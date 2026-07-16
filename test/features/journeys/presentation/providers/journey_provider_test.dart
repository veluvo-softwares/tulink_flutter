import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
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
    );
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
