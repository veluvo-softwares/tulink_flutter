import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guards for the single-map architecture.
///
/// These assert over the production source tree rather than through the widget
/// tree, because the thing being protected *is* a property of the source: a
/// second `MapWidget` or a resurrected `/mapview` push would compile, pass every
/// behavioural test, and still reintroduce the divergence the refactor removed.
/// A widget test cannot see a map that some other screen mounts.
void main() {
  final libDir = Directory('lib');

  List<File> dartFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  /// `path:line` for every line in `lib/` matching [pattern], ignoring comments
  /// so that documentation *about* the retired route does not trip the guard.
  List<String> matches(RegExp pattern) {
    final hits = <String>[];
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(line)) hits.add('${file.path}:${i + 1}');
      }
    }
    return hits..sort();
  }

  group('exactly one map exists', () {
    test('production code instantiates a single MapWidget', () {
      final instantiations = matches(RegExp(r'MapWidget\('));

      expect(
        instantiations,
        hasLength(1),
        reason:
            'TuLink renders one persistent map. A second MapWidget means two '
            'native surfaces and two independent camera/route states, which is '
            'exactly the divergence this architecture removes. Found: '
            '$instantiations',
      );
      expect(
        instantiations.single,
        contains('persistent_tulink_map.dart'),
        reason: 'the one map must be the shared persistent surface',
      );
    });

    test('the redirect kept for legacy deep links contains no map', () {
      final redirect = File(
        'lib/features/maps/presentation/map_route_redirect_screen.dart',
      ).readAsStringSync();

      expect(redirect.contains('MapWidget'), isFalse);
      expect(
        redirect.contains('NavigationHelper.toHomeAndClearStack'),
        isTrue,
        reason: 'a legacy /mapview entry must land back on the shell',
      );
    });
  });

  group('no flow navigates to a map screen', () {
    test('nothing pushes the retired /mapview route', () {
      // Covers start journey, invitation acceptance, the journey-started
      // event, resume, and join-by-code in one assertion: none of them may
      // reach a map by navigation, because entering a journey is now a state
      // change on the map already on screen.
      final pushes = matches(
        RegExp(r'''push[A-Za-z]*Named\(\s*\n?\s*[^)]*['"]/mapview['"]'''),
      );
      expect(
        pushes,
        isEmpty,
        reason:
            'entering a journey must not replace the map the user is looking '
            'at. Found pushes at: $pushes',
      );
    });

    test('the only /mapview reference left is the redirect route name', () {
      final references = matches(RegExp(r"""['"]/mapview['"]"""));
      expect(references, hasLength(1));
      expect(references.single, contains('map_route_redirect_screen.dart'));
    });

    test('the retired TulinkMapScreen is gone entirely', () {
      expect(
        File(
          'lib/features/maps/presentation/tulink_map_screen.dart',
        ).existsSync(),
        isFalse,
      );
      expect(matches(RegExp('TulinkMapScreen')), isEmpty);
    });
  });

  group('no flow navigates to a journey page', () {
    test('nothing pushes JourneyPreviewScreen', () {
      // A staged or live journey is an overlay on the persistent map, not a
      // page. A push here would leave the map behind and reintroduce the
      // second-surface problem from the other direction.
      final pushes = matches(
        RegExp(r'''push[A-Za-z]*Named\(\s*
?\s*[^)]*JourneyPreviewScreen'''),
      );
      expect(pushes, isEmpty, reason: 'found pushes at: $pushes');
    });

    test(
      'the preview screen survives only as a routable compatibility entry',
      () {
        // It may still be reachable by name for old links; it must not be a
        // normal lifecycle destination, which the push assertion above enforces.
        final references = matches(RegExp('JourneyPreviewScreen'));
        for (final reference in references) {
          expect(
            reference.startsWith('lib/core/navigation/app_router.dart') ||
                reference.startsWith(
                  'lib/features/journeys/presentation/pages/'
                  'journey_preview_screen.dart',
                ),
            isTrue,
            reason: 'unexpected production reference at $reference',
          );
        }
      },
    );
  });

  group('cross-layer wiring no widget test can observe', () {
    // These stay as source guards because the defect lives in how two widgets
    // are connected: ConvoyStatusBar can be tested in isolation (see
    // live_back_wiring_test.dart) and Home can be tested in isolation, but
    // neither sees which callback the live layer hands down between them.
    // That gap is exactly where the shipped Back bug lived.
    test('the live layer hands Back the collapse callback', () {
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();

      expect(
        live.contains('onBack: widget.onBack'),
        isTrue,
        reason: 'Back must be forwarded to the host, not handled locally',
      );
      expect(
        live.contains('onBack: widget.onExit'),
        isFalse,
        reason: 'wiring Back to exit tears down a running journey',
      );
    });

    test('surface recreation has exactly one owner', () {
      // Two owners produced two generation bumps and two restore passes for a
      // single resume.
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();
      final home = File(
        'lib/features/home/presentation/screens/home_screen.dart',
      ).readAsStringSync();

      expect(
        live.contains('controller.recreate()'),
        isFalse,
        reason: 'the live layer must react to rebuilds, not trigger them',
      );
      expect(home.contains('_mapController.recreate()'), isTrue);
    });
  });

  group('join and observe are not gated on location', () {
    test('only leader activation retains a location precondition', () {
      // Phase 1's invariant: membership, journey events and reconnect must
      // survive a denied permission. Only activating a new convoy — which every
      // member then navigates off — may require the leader's own location.
      final gated = matches(
        RegExp(r'ensureLocationReady\('),
      ).where((hit) => !hit.startsWith('lib/core/widgets/')).toList();

      const allowedActivationSites = [
        'lib/features/home/presentation/screens/home_screen.dart',
        'lib/features/journeys/presentation/pages/journey_preview_screen.dart',
      ];

      for (final hit in gated) {
        expect(
          allowedActivationSites.any(hit.startsWith),
          isTrue,
          reason:
              'a location gate outside leader activation blocks join/observe: '
              '$hit',
        );
      }
      expect(
        gated,
        hasLength(3),
        reason: 'exactly the three leader-activation gates remain: $gated',
      );
    });
  });

  group('the shell hosts the map unconditionally', () {
    test('the map is not rendered inside a tab or overlay branch', () {
      final home = File(
        'lib/features/home/presentation/screens/home_screen.dart',
      ).readAsLinesSync();

      final mapLine = home.indexWhere(
        (line) => line.contains('PersistentTulinkMap('),
      );
      expect(mapLine, isNot(-1), reason: 'the shell must host the map');

      // The map sits directly in the Stack's child list. If it were guarded by
      // a tab check it would unmount on every tab change, throwing away the
      // camera and the drawn route — the regression this whole part exists to
      // prevent.
      final preceding = home.sublist(0, mapLine).reversed.take(6).join('\n');
      expect(
        preceding.contains('selectedTab') ||
            preceding.contains('experience ==') ||
            preceding.contains('isJourneyRunning'),
        isFalse,
        reason: 'the persistent map must not be conditional on tab or state',
      );
    });
  });
}
