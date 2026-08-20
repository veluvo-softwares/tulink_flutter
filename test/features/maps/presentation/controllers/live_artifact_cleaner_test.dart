import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/live_artifact_cleaner.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/live_map_artifacts.dart';

/// The live convoy draws onto the *shared* surface, so nothing is reclaimed
/// when its widget unmounts. These tests drive the real cleanup policy through
/// a recording port — the previous coverage only checked that a method name
/// appeared in Home's source, which passed while nothing was actually removed.
void main() {
  late _RecordingArtifacts artifacts;
  late int generation;
  late String? selectedJourney;

  LiveArtifactCleaner build() => LiveArtifactCleaner(
    artifacts: () => artifacts,
    currentGeneration: () => generation,
    currentJourneyId: () => selectedJourney,
  );

  setUp(() {
    artifacts = _RecordingArtifacts();
    generation = 0;
    selectedJourney = 'j1';
  });

  group('removal actually happens', () {
    test('clearing removes the live drawings', () async {
      await build().clear(journeyId: 'j1');

      expect(
        artifacts.clearCount,
        1,
        reason: 'Done must physically remove the route and markers',
      );
    });

    test('every live layer and source is covered', () {
      // A drawing absent from this inventory survives onto the next journey.
      expect(
        LiveMapArtifactIds.layers,
        containsAll(<String>[
          'actual-route-line',
          'actual-route-bg',
          'journey-destination-ring',
          'journey-destination-dot',
          'snapped-puck-ring',
          'snapped-puck-dot',
          'raw-puck-ring',
          'raw-puck-dot',
          'convoy-members-layer',
          'convoy-members-label-layer',
          'convoy-members-heading-layer',
        ]),
      );
      expect(
        LiveMapArtifactIds.sources,
        containsAll(<String>[
          'actual-route-source',
          'journey-destination-source',
          'snapped-puck-source',
          'raw-puck-source',
          'convoy-members-source',
        ]),
      );
    });

    test('repeating Done is a no-op rather than a second pass', () async {
      final cleaner = build();
      await cleaner.clear(journeyId: 'j1');
      await cleaner.clear(journeyId: 'j1');

      expect(artifacts.clearCount, 1);
    });

    test('a restarted journey can be cleaned again', () async {
      final cleaner = build();
      await cleaner.clear(journeyId: 'j1');
      // "Go again" redraws, so the new drawings must be removable.
      cleaner.forget('j1');
      await cleaner.clear(journeyId: 'j1');

      expect(artifacts.clearCount, 2);
    });
  });

  group('a late cleanup cannot erase the wrong journey', () {
    test('rejected when another journey has taken over', () async {
      final cleaner = build();
      selectedJourney = 'j2';

      await cleaner.clear(journeyId: 'j1');

      expect(
        artifacts.clearCount,
        0,
        reason: "clearing j1 now would wipe j2's route",
      );
    });

    test('a request queued behind another is dropped after a rebuild', () async {
      // A cleanup already touching the style is harmless — those calls just
      // fail against a dead surface. What must not happen is a *queued* request
      // starting against a surface that was rebuilt while it waited.
      final gate = Completer<void>();
      artifacts.gate = gate.future;
      final cleaner = build();

      final first = cleaner.clear(journeyId: 'j1');
      final queued = cleaner.clear(journeyId: 'j1', force: true);
      generation++; // resume rebuilt the native surface
      gate.complete();
      await Future.wait([first, queued]);

      expect(
        artifacts.clearCount,
        1,
        reason: 'the queued pass must not run against the new surface',
      );
    });

    test('work that raced a rebuild is not recorded as cleaned', () async {
      final gate = Completer<void>();
      artifacts.gate = gate.future;
      final cleaner = build();

      final pending = cleaner.clear(journeyId: 'j1');
      generation++;
      gate.complete();
      await pending;

      // It ran against the old surface, so the new surface's copy of these
      // layers is still there and must remain removable.
      artifacts.gate = null;
      await cleaner.clear(journeyId: 'j1');
      expect(artifacts.clearCount, 2);
    });

    test('allowed when nothing else is selected', () async {
      selectedJourney = null;
      await build().clear(journeyId: 'j1');

      expect(artifacts.clearCount, 1);
    });
  });

  group('overlapping requests', () {
    test('are serialised, not interleaved', () async {
      final gate = Completer<void>();
      artifacts.gate = gate.future;
      final cleaner = build();

      final first = cleaner.clear(journeyId: 'j1');
      final second = cleaner.clear(journeyId: 'j1', force: true);
      expect(artifacts.concurrentPeak, lessThanOrEqualTo(1));

      gate.complete();
      await Future.wait([first, second]);

      expect(
        artifacts.concurrentPeak,
        1,
        reason: 'a half-applied removal leaves orphan layers',
      );
    });
  });

  test('missing artifacts port is survivable', () async {
    final cleaner = LiveArtifactCleaner(
      artifacts: () => null,
      currentGeneration: () => 0,
      currentJourneyId: () => null,
    );

    await expectLater(cleaner.clear(journeyId: 'j1'), completes);
  });
}

class _RecordingArtifacts implements LiveMapArtifacts {
  int clearCount = 0;
  int _active = 0;
  int concurrentPeak = 0;
  Future<void>? gate;

  @override
  Future<void> clearAll() async {
    _active++;
    concurrentPeak = _active > concurrentPeak ? _active : concurrentPeak;
    if (gate != null) await gate;
    clearCount++;
    _active--;
  }
}
