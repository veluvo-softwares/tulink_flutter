import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/presentation/services/live_journey_coordinator.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

void main() {
  Journey journey(String id, JourneyStatus status) => Journey(
    id: id,
    name: id,
    leaderId: 'leader',
    status: status,
    destination: const LatLng(latitude: -1.2, longitude: 36.8),
    destinationAddress: 'Nairobi',
    lagThresholdMeters: 100,
  );

  late bool eligible;
  late Journey? selected;
  late String? ownedJourneyId;
  late bool subscribed;
  late List<String> operations;
  late LiveJourneyCoordinator coordinator;

  setUp(() {
    eligible = true;
    selected = null;
    ownedJourneyId = null;
    subscribed = false;
    operations = [];
    coordinator = LiveJourneyCoordinator(
      canCoordinate: () => eligible,
      currentJourney: () => selected,
      coordinatingJourneyId: () => ownedJourneyId,
      isSubscribed: () => subscribed,
      startCoordination: (journeyId) async {
        operations.add('start:$journeyId');
        ownedJourneyId = journeyId;
        subscribed = true;
      },
      stopCoordination: () async {
        operations.add('stop');
        ownedJourneyId = null;
        subscribed = false;
      },
      refreshActiveJourneys: () async => operations.add('refresh'),
      recoverAfterResume: () async => operations.add('recover'),
    );
  });

  test('active journey starts without a journey screen owner', () async {
    selected = journey('A', JourneyStatus.ACTIVE);

    await coordinator.reconcile();

    expect(operations, ['start:A']);
  });

  test('a joined room is not restarted when GPS is unavailable', () async {
    selected = journey('A', JourneyStatus.ACTIVE);
    ownedJourneyId = 'A';
    subscribed = true;

    await coordinator.reconcile();
    await coordinator.reconcile();

    expect(operations, isEmpty);
  });

  test(
    'logout or terminal journey state stops app-owned coordination',
    () async {
      selected = journey('A', JourneyStatus.ACTIVE);
      ownedJourneyId = 'A';
      subscribed = true;
      eligible = false;

      await coordinator.reconcile();

      expect(operations, ['stop']);
    },
  );

  test(
    'state changing during start is drained to the newest journey',
    () async {
      final firstStart = Completer<void>();
      coordinator = LiveJourneyCoordinator(
        canCoordinate: () => eligible,
        currentJourney: () => selected,
        coordinatingJourneyId: () => ownedJourneyId,
        isSubscribed: () => subscribed,
        startCoordination: (journeyId) async {
          operations.add('start:$journeyId');
          if (journeyId == 'A') await firstStart.future;
          ownedJourneyId = journeyId;
          subscribed = true;
        },
        stopCoordination: () async {
          operations.add('stop');
          ownedJourneyId = null;
          subscribed = false;
        },
        refreshActiveJourneys: () async {},
        recoverAfterResume: () async {},
      );

      selected = journey('A', JourneyStatus.ACTIVE);
      final reconciling = coordinator.reconcile();
      await Future<void>.delayed(Duration.zero);
      selected = journey('B', JourneyStatus.ACTIVE);
      final newest = coordinator.reconcile();
      firstStart.complete();

      await Future.wait([reconciling, newest]);
      expect(operations, ['start:A', 'start:B']);
      expect(ownedJourneyId, 'B');
    },
  );

  test(
    'resume refreshes, restores ownership, then recovers missed state',
    () async {
      selected = journey('A', JourneyStatus.ACTIVE);

      await coordinator.onAppResumed();

      expect(operations, ['refresh', 'start:A', 'recover']);
    },
  );

  test('duplicate resume signals share one recovery transaction', () async {
    selected = journey('A', JourneyStatus.ACTIVE);
    final refreshGate = Completer<void>();
    var refreshCount = 0;
    coordinator = LiveJourneyCoordinator(
      canCoordinate: () => eligible,
      currentJourney: () => selected,
      coordinatingJourneyId: () => ownedJourneyId,
      isSubscribed: () => subscribed,
      startCoordination: (journeyId) async {
        ownedJourneyId = journeyId;
        subscribed = true;
      },
      stopCoordination: () async {},
      refreshActiveJourneys: () async {
        refreshCount++;
        await refreshGate.future;
      },
      recoverAfterResume: () async {},
    );

    final first = coordinator.onAppResumed();
    final second = coordinator.onAppResumed();
    refreshGate.complete();
    await Future.wait([first, second]);

    expect(refreshCount, 1);
  });
}
