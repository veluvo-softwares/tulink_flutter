import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/state/live_artifact_coordinator.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/live_artifact_cleaner.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/live_map_artifacts.dart';

/// Done must be atomic: the summary stays up, in an explicit cleaning state,
/// until the shared surface is genuinely clear — and journey B must not be
/// adopted while journey A's removals are still running.
///
/// The shipped handler launched cleanup without awaiting it and dismissed the
/// summary immediately, so "exploring" was reported over a map that still had
/// A's route on it, and B drew into the middle of A's deletions.
void main() {
  late _RecordingArtifacts artifacts;
  late int generation;
  late String? selected;
  late LiveArtifactCleaner cleaner;
  late LiveArtifactCoordinator coordinator;

  setUp(() {
    artifacts = _RecordingArtifacts();
    generation = 0;
    selected = null;
    cleaner = LiveArtifactCleaner(
      artifacts: () => artifacts,
      currentGeneration: () => generation,
      currentJourneyId: () => selected,
    );
    coordinator = LiveArtifactCoordinator(cleaner: cleaner);
  });

  test(
    'Done reports exploring only after the surface is really clear',
    () async {
      coordinator.adopt('A');
      final gate = Completer<void>();
      artifacts.gate = gate.future;

      final states = <bool>[];
      final done = coordinator.clear(
        onStateChanged: () => states.add(coordinator.isCleaning),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        coordinator.isCleaning,
        isTrue,
        reason: 'the transition has an explicit, observable cleaning state',
      );
      expect(coordinator.journeyId, 'A', reason: 'still dirty');

      gate.complete();
      expect(await done, isTrue);

      expect(states, [true, false]);
      expect(coordinator.isCleaning, isFalse);
      expect(coordinator.journeyId, isNull);
      expect(artifacts.clearCount, 1);
    },
  );

  test('adopting B waits for A cleanup to settle', () async {
    coordinator.adopt('A');
    final gate = Completer<void>();
    artifacts.gate = gate.future;

    final done = coordinator.clear();
    await Future<void>.delayed(Duration.zero);

    var settled = false;
    final waiting = coordinator.settle().then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(
      settled,
      isFalse,
      reason: "B must not draw while A's removals are still running",
    );

    gate.complete();
    await done;
    await waiting;
    expect(settled, isTrue);
  });

  test('a failed cleanup leaves an honest dirty state', () async {
    coordinator.adopt('A');
    // Another journey takes the surface, so the cleanup is rejected.
    selected = 'B';

    expect(await coordinator.clear(), isFalse);
    expect(
      coordinator.journeyId,
      'A',
      reason: 'the surface must not be reported as clean when it is not',
    );
    expect(coordinator.isCleaning, isFalse);
  });

  test('a cleanup that throws is reported as failed, not as clean', () async {
    coordinator.adopt('A');
    artifacts.throwOnClear = true;

    expect(await coordinator.clear(), isFalse);
    expect(coordinator.journeyId, 'A');
    expect(coordinator.isCleaning, isFalse);
  });

  test('two Done taps are one cleanup', () async {
    coordinator.adopt('A');
    final gate = Completer<void>();
    artifacts.gate = gate.future;

    final first = coordinator.clear();
    await Future<void>.delayed(Duration.zero);
    final second = coordinator.clear();

    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(
      artifacts.clearCount,
      1,
      reason: 'the second tap is the same request',
    );
  });

  test(
    're-entering a journey makes its fresh drawings removable again',
    () async {
      coordinator.adopt('A');
      expect(await coordinator.clear(), isTrue);

      // "Go again" redraws A.
      coordinator.adopt('A');
      expect(await coordinator.clear(), isTrue);
      expect(artifacts.clearCount, 2);
    },
  );

  test('clearing with nothing drawn is a no-op success', () async {
    expect(await coordinator.clear(), isTrue);
    expect(artifacts.clearCount, 0);
  });
}

class _RecordingArtifacts implements LiveMapArtifacts {
  int clearCount = 0;
  Future<void>? gate;
  bool throwOnClear = false;

  @override
  Future<bool> clearAll({bool Function()? isStillValid}) async {
    if (gate != null) await gate;
    if (throwOnClear) throw StateError('style is gone');
    if (!(isStillValid?.call() ?? true)) return false;
    clearCount++;
    return true;
  }
}
