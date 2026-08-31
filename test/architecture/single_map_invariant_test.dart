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
    test('the retired journey preview page is gone entirely', () {
      // It consumed `journey-started` before its fetch succeeded and started
      // coordination without checking the fetched identity or status, so a
      // transient GET failure lost the event permanently and a slow response
      // could coordinate the wrong journey. It was the last routable path with
      // that behaviour. Deleting it removes the class of bug instead of
      // maintaining the staging rules in a second place.
      expect(
        File(
          'lib/features/journeys/presentation/pages/'
          'journey_preview_screen.dart',
        ).existsSync(),
        isFalse,
      );
      expect(matches(RegExp('JourneyPreviewScreen')), isEmpty);
    });

    test('the legacy preview route still resolves, via the redirect', () {
      // Old deep links and notification payloads must not land on the
      // undefined-route screen.
      final router = File(
        'lib/core/navigation/app_router.dart',
      ).readAsStringSync();
      expect(
        router.contains('MapRouteRedirectScreen.legacyJourneyPreviewRouteName'),
        isTrue,
        reason: '/journey-preview must still be routable',
      );

      final redirect = File(
        'lib/features/maps/presentation/map_route_redirect_screen.dart',
      ).readAsStringSync();
      expect(redirect.contains("'/journey-preview'"), isTrue);
    });
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

    test('Home delegates the behaviours that are tested elsewhere', () {
      // These four collaborators exist so the rules they own can be driven
      // behaviourally. If Home stops using one, its tests keep passing while
      // production regresses — which is precisely the failure mode this whole
      // corrective pass exists to remove. So the delegation itself is pinned.
      final home = File(
        'lib/features/home/presentation/screens/home_screen.dart',
      ).readAsStringSync();

      const delegations = {
        // 1.1 pending-room recovery + the Reconnect control
        'PendingJourneyStaging(':
            'pending_journey_staging_test.dart drives the real Reconnect',
        // 1.9 platform Back at the Home/live boundary
        'LiveJourneyBackBoundary(':
            'live_journey_back_boundary_test.dart drives the real PopScope',
        // 1.6 trailing-edge roster coalescing
        '_rosterRefresh.record(':
            'roster_refresh_coalescer_test.dart owns the burst rules',
        // 1.7 invite claim taken before the picker opens
        '_inviteDispatcher.dispatch<':
            'staged_invite_dispatcher_test.dart owns the duplicate-tap rule',
        // 1.8 Done awaits cleanup before reporting exploring
        '_artifactCoordinator.clear(':
            'live_artifact_coordinator_test.dart owns the Done transition',
      };

      for (final entry in delegations.entries) {
        expect(
          home.contains(entry.key),
          isTrue,
          reason: 'Home must call ${entry.key} — ${entry.value}',
        );
      }
    });

    test('Done awaits cleanup, and adoption waits for it to settle', () {
      // The shipped defect was a fire-and-forget cleanup: Done dismissed the
      // summary immediately, so "exploring" was reported over a map that still
      // had the finished route on it, and journey B drew into the middle of
      // journey A's removals.
      final home = File(
        'lib/features/home/presentation/screens/home_screen.dart',
      ).readAsStringSync();

      expect(
        home.contains('final cleaned = await _clearFinishedJourneyMap();'),
        isTrue,
        reason:
            'Done must await live, preview, and destination cleanup before '
            'exposing the follower Home map',
      );
      expect(home.contains('await _clearPreviewRoute();'), isTrue);
      expect(home.contains('await _clearDestinationAnnotations();'), isTrue);
      // The other teardown path (ended/left) has no summary to hold, so it does
      // not await — instead, adoption of the *next* journey blocks on the same
      // coordinator, which closes the same race from the other side.
      expect(
        home.contains('await _artifactCoordinator.settle();'),
        isTrue,
        reason: 'B must not be drawn while A is still being removed',
      );
    });

    test(
      'resume probes the retained surface before exceptional recreation',
      () {
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
        expect(home.contains('_mapController.ensureResponsive()'), isTrue);
        expect(
          home.contains('_mapController.recreate()'),
          isFalse,
          reason: 'healthy resume must retain route, camera and native style',
        );
      },
    );

    test('live transport and native location each have one app owner', () {
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();
      final home = File(
        'lib/features/home/presentation/screens/home_screen.dart',
      ).readAsStringSync();
      final invites = File(
        'lib/features/invites/presentation/pages/invitations_screen.dart',
      ).readAsStringSync();

      expect(live.contains('startCoordination('), isFalse);
      expect(home.contains('startCoordination('), isFalse);
      expect(invites.contains('startCoordination('), isFalse);
      expect(
        live.contains('.getPositionStream('),
        isFalse,
        reason: 'map consumers must share JourneyLocationService',
      );
    });
  });

  group('cleanup owns every live drawing', () {
    // A layer or source the live convoy adds but the inventory does not name
    // survives Done and reappears on the next journey. Only the source tree can
    // decide this: a widget test can assert that what *is* in the inventory is
    // removed, but not that the inventory is complete.
    test('every id the live layer adds is in the removal inventory', () {
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();
      final inventory = File(
        'lib/features/maps/presentation/controllers/live_map_artifacts.dart',
      ).readAsStringSync();

      // Every id the live layer declares for a style object, plus every
      // literal handed straight to a layer/source constructor.
      final declared = RegExp(
        "const\\s+(?:String\\s+)?\\w*(?:[Ss]ource|[Ll]ayer|[Ll]ine|[Bb]g|[Rr]ing|[Dd]ot)Id"
        "\\s*=\\s*'([^']+)'",
      ).allMatches(live).map((m) => m.group(1)!).toSet();

      final inline = RegExp(
        "\\bid:\\s*'([^']+)'",
      ).allMatches(live).map((m) => m.group(1)!).toSet();

      final all = {...declared, ...inline};
      expect(
        all,
        isNotEmpty,
        reason: 'the scan must actually find the live layer ids',
      );

      final missing = all.where((id) => !inventory.contains("'$id'")).toList()
        ..sort();

      expect(
        missing,
        isEmpty,
        reason:
            'these live drawings would survive Done and reappear on the next '
            'journey: $missing',
      );
    });

    test('sources are listed after the layers that reference them', () {
      // Mapbox refuses to remove a source while a layer still references it,
      // so the ordering in the inventory is load-bearing.
      final inventory = File(
        'lib/features/maps/presentation/controllers/live_map_artifacts.dart',
      ).readAsStringSync();

      expect(
        inventory.indexOf('static const List<String> layers'),
        lessThan(inventory.indexOf('static const List<String> sources')),
      );
    });
  });

  group('native directional location puck', () {
    test('live journeys use hybrid heading/course puck bearing', () {
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();

      expect(
        live.contains('PuckBearing.HEADING when position.speed >= 2.5'),
        isTrue,
        reason:
            'stationary rotation must use device heading before switching to '
            'course at driving speed',
      );
      expect(
        live.contains('PuckBearing.COURSE when position.speed <= 1.0'),
        isTrue,
      );
      expect(
        live.contains('await _setBuiltInPuckEnabled(true);'),
        isTrue,
        reason: 'the native Mapbox location component must remain enabled',
      );
      expect(
        live.contains('Future<void> _drawLegacySnappedPuck'),
        isFalse,
        reason: 'the retired circle puck must not become a second renderer',
      );
      expect(
        live.contains('Future<void> _renderRawPuck'),
        isFalse,
        reason: 'raw GPS must use the same native puck as active navigation',
      );
    });
  });

  group('destination puck styling', () {
    test('preview and live journeys use the Tulink sunset orange token', () {
      final home = File(
        'lib/features/home/presentation/screens/home_screen.dart',
      ).readAsStringSync();
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();

      expect(
        home.contains('TulinkColors.light.sunsetOrange.toARGB32()'),
        isTrue,
      );
      expect(
        live.contains(
          'final destinationColor = '
          'TulinkColors.light.sunsetOrange;',
        ),
        isTrue,
      );
      expect(
        live
            .substring(
              live.indexOf('Future<void> _drawDestinationPin'),
              live.indexOf('Future<void> _updateMarkers'),
            )
            .contains('0xFFE8002D'),
        isFalse,
        reason: 'the retired red destination puck must not return',
      );
    });
  });

  group('live route ownership', () {
    test('each client calculates from its own fix, not the leader route', () {
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();
      final routeSetup = live.substring(
        live.indexOf('Future<void> _drawActualRouteInternal'),
        live.indexOf('Future<void> _handleReroute'),
      );

      expect(routeSetup.contains('mapProvider.fetchRoute('), isTrue);
      expect(routeSetup.contains('originLat: originLat'), isTrue);
      expect(routeSetup.contains('originLng: originLng'), isTrue);
      expect(routeSetup.contains('fetchCanonicalRoute'), isFalse);
      expect(routeSetup.contains('replaceCanonicalRoute'), isFalse);
    });
  });

  group('terminal route draw barrier', () {
    test('confirmed end invalidates any route response still in flight', () {
      final live = File(
        'lib/features/maps/presentation/live_journey_experience.dart',
      ).readAsStringSync();

      expect(live.contains('final routeDrawEpoch = _routeDrawEpoch;'), isTrue);
      expect(live.contains('routeDrawEpoch == _routeDrawEpoch'), isTrue);
      expect(live.contains('_invalidateRouteDrawing();'), isTrue);
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
        hasLength(2),
        reason:
            'exactly the two leader-activation gates remain — starting a new '
            'draft, and starting a staged journey: $gated',
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
