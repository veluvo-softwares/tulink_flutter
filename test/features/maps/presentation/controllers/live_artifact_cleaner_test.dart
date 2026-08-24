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
      // A *queued* request must never start against a surface that was rebuilt
      // while it waited, and the in-flight one must abandon itself as soon as
      // the rebuild is visible rather than running its remaining removals into
      // a style that no longer exists.
      final gate = Completer<void>();
      artifacts.gate = gate.future;
      final cleaner = build();

      final first = cleaner.clear(journeyId: 'j1');
      final queued = cleaner.clear(journeyId: 'j1', force: true);
      generation++; // resume rebuilt the native surface
      gate.complete();
      final results = await Future.wait([first, queued]);

      expect(results, [
        false,
        false,
      ], reason: 'neither pass may report the new surface as cleaned');
      expect(
        artifacts.clearCount,
        0,
        reason: 'no pass may complete against the new surface',
      );
    });

    test('work that raced a rebuild is not recorded as cleaned', () async {
      final gate = Completer<void>();
      artifacts.gate = gate.future;
      final cleaner = build();

      final pending = cleaner.clear(journeyId: 'j1');
      generation++;
      gate.complete();
      expect(await pending, isFalse);

      // The new surface's copy of these layers is still there, so the journey
      // must remain removable without needing `force`.
      artifacts.gate = null;
      expect(await cleaner.clear(journeyId: 'j1'), isTrue);
      expect(artifacts.clearCount, 1);
    });

    test('a delayed cleanup for A stops the moment B takes the map', () async {
      // The shipped race: Done launched A's cleanup without awaiting it, so
      // B could start drawing while A was still deleting. The removals are
      // sequential platform calls, so ownership must be re-checked between
      // them — checking once up front let the rest of A's pass delete B's
      // route, destination, peers and puck.
      final gate = Completer<void>();
      artifacts.gate = gate.future;
      final cleaner = build();

      final pending = cleaner.clear(journeyId: 'j1');
      gate.complete();
      // B takes the map while A's batches are still running.
      await Future<void>.delayed(Duration.zero);
      selectedJourney = 'j2';

      expect(await pending, isFalse);
      expect(
        artifacts.removed.length,
        lessThan(_RecordingArtifacts.batches.length),
        reason: "A's cleanup must stop, not finish deleting B's geometry",
      );
      expect(
        artifacts.clearCount,
        0,
        reason: 'an abandoned pass is not a completed one',
      );
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

  /// Removals actually performed, in order. Modelled as discrete batches so a
  /// test can assert that ownership is re-checked *between* them.
  final List<String> removed = [];

  /// The batches a real cleanup walks: every layer, then every source, then
  /// the annotation manager.
  static const List<String> batches = [
    ...LiveMapArtifactIds.layers,
    ...LiveMapArtifactIds.sources,
    'annotations',
  ];

  @override
  Future<bool> clearAll({bool Function()? isStillValid}) async {
    _active++;
    concurrentPeak = _active > concurrentPeak ? _active : concurrentPeak;
    if (gate != null) await gate;
    try {
      for (final id in batches) {
        // Mirrors MapboxLiveMapArtifacts: ownership is consulted before every
        // removal, not once at the start.
        if (!(isStillValid?.call() ?? true)) return false;
        removed.add(id);
        await Future<void>.delayed(Duration.zero);
      }
      clearCount++;
      return isStillValid?.call() ?? true;
    } finally {
      _active--;
    }
  }
}
