import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/home/presentation/state/map_experience_state.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

/// The single Home map is driven by this derived value. It replaces a set of
/// independent booleans whose combinations could disagree with the providers.
void main() {
  Journey journey(JourneyStatus status) => Journey(
    id: 'j1',
    name: 'Trip to Karen Shopping Centre',
    leaderId: 'leader-1',
    status: status,
    destination: const LatLng(latitude: -1.3234931, longitude: 36.7083102),
    destinationName: 'Karen Shopping Centre',
    destinationAddress: 'Nairobi, Kenya',
    lagThresholdMeters: 500,
  );

  MapExperienceState resolve({
    Journey? currentJourney,
    Journey? completedJourney,
    bool hasDraft = false,
    bool isStarting = false,
    bool isEnding = false,
    bool isCurrentUserLeader = true,
    ConvoyConnectionState connectionState = ConvoyConnectionState.connected,
  }) {
    return resolveMapExperienceState(
      currentJourney: currentJourney,
      completedJourney: completedJourney,
      hasDraft: hasDraft,
      isStarting: isStarting,
      isEnding: isEnding,
      isCurrentUserLeader: isCurrentUserLeader,
      connectionState: connectionState,
    );
  }

  group('steady states', () {
    test('nothing in progress is exploring', () {
      expect(resolve(), MapExperienceState.exploring);
    });

    test('a chosen destination is drafting', () {
      expect(resolve(hasDraft: true), MapExperienceState.drafting);
    });

    test('an active journey on a healthy connection is liveConvoy', () {
      expect(
        resolve(currentJourney: journey(JourneyStatus.ACTIVE)),
        MapExperienceState.liveConvoy,
      );
    });
  });

  group('connection health splits live from recovering', () {
    for (final state in [
      ConvoyConnectionState.error,
      ConvoyConnectionState.reconnecting,
      ConvoyConnectionState.disconnected,
      ConvoyConnectionState.connecting,
    ]) {
      test('an active journey while $state is recovering', () {
        expect(
          resolve(
            currentJourney: journey(JourneyStatus.ACTIVE),
            connectionState: state,
          ),
          MapExperienceState.recovering,
          reason: 'the journey continues; only the connection is degraded',
        );
      });
    }

    test('only a connected socket yields liveConvoy', () {
      // Matches ConvoyStatusBar's refined liveness rule exactly, so the map
      // and the status bar can never disagree about the same connection.
      expect(
        resolve(
          currentJourney: journey(JourneyStatus.ACTIVE),
          connectionState: ConvoyConnectionState.connected,
        ),
        MapExperienceState.liveConvoy,
      );
    });
  });

  group('pending journeys depend on role', () {
    test('a member waits for the leader', () {
      expect(
        resolve(
          currentJourney: journey(JourneyStatus.PENDING),
          isCurrentUserLeader: false,
        ),
        MapExperienceState.waitingForLeader,
      );
    });

    test('the leader still owns the draft and its Start control', () {
      expect(
        resolve(
          currentJourney: journey(JourneyStatus.PENDING),
          isCurrentUserLeader: true,
        ),
        MapExperienceState.drafting,
      );
    });
  });

  group('in-flight operations outrank steady state', () {
    test('ending wins over everything', () {
      expect(
        resolve(
          currentJourney: journey(JourneyStatus.ACTIVE),
          completedJourney: journey(JourneyStatus.COMPLETED),
          isStarting: true,
          isEnding: true,
        ),
        MapExperienceState.ending,
      );
    });

    test('a pending summary outranks a live journey', () {
      expect(
        resolve(
          currentJourney: journey(JourneyStatus.ACTIVE),
          completedJourney: journey(JourneyStatus.COMPLETED),
        ),
        MapExperienceState.completed,
      );
    });

    test('starting outranks the draft it came from', () {
      expect(
        resolve(hasDraft: true, isStarting: true),
        MapExperienceState.starting,
      );
    });
  });

  group('terminal journeys do not pin the map', () {
    test('a completed journey with no summary falls back to the draft', () {
      expect(
        resolve(
          currentJourney: journey(JourneyStatus.COMPLETED),
          hasDraft: true,
        ),
        MapExperienceState.drafting,
      );
    });

    test('a cancelled journey with no draft returns to exploring', () {
      expect(
        resolve(currentJourney: journey(JourneyStatus.CANCELLED)),
        MapExperienceState.exploring,
      );
    });
  });

  group('transitions keep the one map continuous', () {
    test('a waiting member goes live without the map losing geometry', () {
      // The member sits on waitingForLeader, then the leader starts. Both
      // states hold geometry, so the destination and route the member is
      // already looking at are never cleared between them.
      const waiting = MapExperienceState.waitingForLeader;
      final live = resolve(currentJourney: journey(JourneyStatus.ACTIVE));

      expect(waiting.holdsJourneyGeometry, isTrue);
      expect(live, MapExperienceState.liveConvoy);
      expect(live.holdsJourneyGeometry, isTrue);
    });

    test('drafting through to live never drops geometry mid-flight', () {
      // This ordering is the whole point of the single map: if any state in
      // the chain reported "no geometry", the route would visibly reset at
      // that moment.
      final chain = [
        resolve(hasDraft: true, isStarting: true),
        resolve(currentJourney: journey(JourneyStatus.ACTIVE)),
        resolve(
          currentJourney: journey(JourneyStatus.ACTIVE),
          connectionState: ConvoyConnectionState.reconnecting,
        ),
      ];

      expect(
        chain.map((state) => state.holdsJourneyGeometry),
        everyElement(isTrue),
        reason:
            'no step from starting to a degraded live convoy may reset '
            'the map',
      );
    });

    test('a degraded connection keeps the journey on the map', () {
      // Recovering is still a running journey — losing the socket must not
      // tear down the route the driver is following.
      final recovering = resolve(
        currentJourney: journey(JourneyStatus.ACTIVE),
        connectionState: ConvoyConnectionState.error,
      );

      expect(recovering, MapExperienceState.recovering);
      expect(recovering.isJourneyRunning, isTrue);
      expect(recovering.holdsJourneyGeometry, isTrue);
    });

    test('a draft alone never starts a journey by itself', () {
      // "Go again" rebuilds a draft. It must land on drafting — not starting,
      // and not live — so the user still has to press Start.
      final draft = resolve(hasDraft: true);

      expect(draft, MapExperienceState.drafting);
      expect(draft.isJourneyRunning, isFalse);
      expect(draft.isBusy, isFalse);
    });

    test('dismissing a completion summary returns the map to exploring', () {
      expect(
        resolve(completedJourney: journey(JourneyStatus.COMPLETED)),
        MapExperienceState.completed,
      );
      // Done clears both the summary and the draft it came from.
      expect(resolve(), MapExperienceState.exploring);
    });
  });

  group('ending must not pin the experience', () {
    test('a stuck ending flag would hide the completion summary forever', () {
      // Regression: `ending` outranks `completed`, so if the shell fails to
      // clear its teardown flag when the journey finishes, the summary can
      // never be reached. Runtime testing caught exactly this.
      final stillEnding = resolve(
        completedJourney: journey(JourneyStatus.COMPLETED),
        isEnding: true,
      );
      expect(stillEnding, MapExperienceState.ending);

      final cleared = resolve(
        completedJourney: journey(JourneyStatus.COMPLETED),
      );
      expect(
        cleared,
        MapExperienceState.completed,
        reason: 'clearing the teardown flag must reveal the summary',
      );
    });

    test('ending and completed both keep the journey owning the screen', () {
      // Browse chrome is gated on this same predicate, so a mismatch is what
      // left a stale draft sheet — with a live Start button — under the
      // completion summary.
      expect(MapExperienceState.ending.hidesNavigationTabs, isTrue);
      expect(MapExperienceState.completed.hidesNavigationTabs, isTrue);
      expect(MapExperienceState.starting.hidesNavigationTabs, isTrue);
    });
  });

  group('predicates', () {
    test('isJourneyRunning covers live and recovering', () {
      expect(MapExperienceState.liveConvoy.isJourneyRunning, isTrue);
      expect(MapExperienceState.recovering.isJourneyRunning, isTrue);
      expect(MapExperienceState.drafting.isJourneyRunning, isFalse);
    });

    test('holdsJourneyGeometry keeps the route through transitions', () {
      // These are exactly the states where clearing the route would cause the
      // visible reset the single-map work exists to prevent.
      expect(MapExperienceState.starting.holdsJourneyGeometry, isTrue);
      expect(MapExperienceState.liveConvoy.holdsJourneyGeometry, isTrue);
      expect(MapExperienceState.ending.holdsJourneyGeometry, isTrue);
      expect(MapExperienceState.waitingForLeader.holdsJourneyGeometry, isTrue);
      expect(MapExperienceState.exploring.holdsJourneyGeometry, isFalse);
    });

    test('tab bar is hidden exactly while the journey owns the screen', () {
      // The navigation shell reads this instead of deriving its own state, so
      // the two can never disagree about whether tabs may be shown.
      for (final state in [
        MapExperienceState.liveConvoy,
        MapExperienceState.recovering,
        MapExperienceState.waitingForLeader,
        MapExperienceState.starting,
        MapExperienceState.ending,
        MapExperienceState.completed,
      ]) {
        expect(
          state.hidesNavigationTabs,
          isTrue,
          reason: '$state must not offer tabs it cannot honour',
        );
      }

      for (final state in [
        MapExperienceState.exploring,
        MapExperienceState.drafting,
      ]) {
        expect(
          state.hidesNavigationTabs,
          isFalse,
          reason: '$state is browsing — the tabs are the point',
        );
      }
    });

    test('every state has a defined tab-bar answer', () {
      // A new state defaulting to "show tabs" would silently regress the rule.
      for (final state in MapExperienceState.values) {
        expect(() => state.hidesNavigationTabs, returnsNormally);
      }
      expect(MapExperienceState.values, hasLength(8));
    });

    test('isBusy marks operations that must not be abandoned', () {
      expect(MapExperienceState.starting.isBusy, isTrue);
      expect(MapExperienceState.ending.isBusy, isTrue);
      expect(MapExperienceState.liveConvoy.isBusy, isFalse);
    });
  });
}
