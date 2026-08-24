import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/home/presentation/widgets/pending_journey_staging.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/widgets/pending_journey_overlay.dart';

/// Pending-room recovery, driven through the widget Home actually renders.
///
/// The overlay has supported `hasRoomFailure` / `onReconnectRoom` /
/// `isReconnectingRoom` for a while, but no host passed them — so the explicit
/// listener-only reconnect required of a waiting member was unreachable in the
/// shipped app while every overlay unit test still passed. These tests find and
/// tap the *real* control and assert on the real state machine behind it.
void main() {
  Journey journey({String id = 'j1'}) => Journey(
    id: id,
    name: 'Trip to Karen Shopping Centre',
    leaderId: 'leader-1',
    status: JourneyStatus.PENDING,
    destination: const LatLng(latitude: -1.3234931, longitude: 36.7083102),
    destinationName: 'Karen Shopping Centre',
    destinationAddress: 'Nairobi, Kenya',
    lagThresholdMeters: 500,
  );

  /// No backoff, so the bounded automatic retries resolve inside the test.
  Duration noBackoff(int attempt) => Duration.zero;

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.tulinkTheme,
      home: Scaffold(body: Stack(children: [child])),
    ),
  );

  // Addressed by key, not by label: the control swaps its child for a spinner
  // while a retry is running.
  final reconnect = find.byKey(PendingJourneyOverlay.reconnectRoomKey);

  testWidgets(
    'a failed room join surfaces a Reconnect that recovers, then the leader '
    'start transitions exactly once',
    (tester) async {
      final joinAttempts = <String>[];
      var succeed = false;
      var starts = 0;

      // The production callback Home wires to `journey-started` recovery.
      void retryStart() => starts++;

      await pump(
        tester,
        PendingJourneyStaging(
          journey: journey(),
          isLeader: false,
          leaderName: 'Amina',
          onDismiss: () {},
          retryBackoff: noBackoff,
          onRetryStart: retryStart,
          joinRoom: (id) async {
            joinAttempts.add(id);
            return succeed;
          },
        ),
      );

      // Bounded automatic retries run first — the user is not shown a control
      // for something the app can still fix by itself.
      await tester.pumpAndSettle();
      expect(
        joinAttempts,
        ['j1', 'j1', 'j1'],
        reason: 'one initial attempt plus two bounded automatic retries',
      );

      // Only once they are exhausted does the explicit control appear.
      expect(
        find.text('Not receiving live updates — you may miss the start.'),
        findsOneWidget,
      );
      expect(reconnect, findsOneWidget);

      // It is a real tap target, not a cramped text button.
      final size = tester.getSize(reconnect);
      expect(
        size.height,
        greaterThanOrEqualTo(PendingJourneyOverlay.kRecoveryControlMinSize),
        reason: 'the only way out of a failed join must be tappable',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(PendingJourneyOverlay.kRecoveryControlMinSize),
      );

      // The user recovers explicitly.
      succeed = true;
      await tester.tap(reconnect);
      await tester.pumpAndSettle();

      expect(joinAttempts.length, 4, reason: 'Reconnect really rejoins');
      expect(
        find.text('Not receiving live updates — you may miss the start.'),
        findsNothing,
        reason: 'a recovered room must stop reporting a failure',
      );
      expect(
        starts,
        1,
        reason:
            'Reconnect re-attempts the missed start exactly once, not once '
            'per rebuild',
      );
    },
  );

  testWidgets('never claims to be reconnecting while nothing is running', (
    tester,
  ) async {
    await pump(
      tester,
      PendingJourneyStaging(
        journey: journey(),
        isLeader: false,
        onDismiss: () {},
        retryBackoff: noBackoff,
        joinRoom: (_) async => false,
      ),
    );
    await tester.pumpAndSettle();

    // Retries are exhausted: the control must be enabled and must not read as
    // in-progress. The shipped copy said "Retrying…" with nothing scheduled.
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Reconnecting…'), findsNothing);
    expect(
      tester.widget<TextButton>(reconnect).onPressed,
      isNotNull,
      reason: 'the explicit control is the only remaining recovery path',
    );
  });

  testWidgets('shows progress and blocks a second tap while retrying', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var attempts = 0;

    await pump(
      tester,
      PendingJourneyStaging(
        journey: journey(),
        isLeader: false,
        onDismiss: () {},
        retryBackoff: noBackoff,
        joinRoom: (_) async {
          attempts++;
          // The first three attempts fail immediately; the explicit retry
          // hangs so the in-flight state is observable.
          if (attempts <= 3) return false;
          return gate.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 3);

    await tester.tap(reconnect);
    await tester.pump();

    // The failure card stays up — with progress — rather than vanishing and
    // leaving the user with no feedback at all.
    expect(
      find.text('Not receiving live updates — you may miss the start.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<TextButton>(reconnect).onPressed,
      isNull,
      reason: 'a retry in flight must not be re-triggerable',
    );

    // A second tap during the retry is a no-op.
    await tester.tap(reconnect, warnIfMissed: false);
    await tester.pump();
    expect(attempts, 4);

    gate.complete(true);
    await tester.pumpAndSettle();
    expect(
      find.text('Not receiving live updates — you may miss the start.'),
      findsNothing,
    );
  });

  testWidgets('an exhausted journey-started transition is actionable', (
    tester,
  ) async {
    var starts = 0;

    await pump(
      tester,
      PendingJourneyStaging(
        journey: journey(),
        isLeader: false,
        onDismiss: () {},
        retryBackoff: noBackoff,
        hasStartFailure: true,
        onRetryStart: () => starts++,
        joinRoom: (_) async => true,
      ),
    );
    await tester.pumpAndSettle();

    // Truthful copy naming what actually failed, plus a control that does
    // something — instead of a toast promising a retry that is not scheduled.
    expect(
      find.textContaining('could not be loaded on this device'),
      findsOneWidget,
    );
    await tester.tap(reconnect);
    await tester.pumpAndSettle();
    expect(starts, 1);
  });

  testWidgets('switching staged journeys abandons the previous attempt', (
    tester,
  ) async {
    final gateA = Completer<bool>();
    final joined = <String>[];

    Widget staging(Journey j) => PendingJourneyStaging(
      journey: j,
      isLeader: false,
      onDismiss: () {},
      retryBackoff: noBackoff,
      joinRoom: (id) async {
        joined.add(id);
        if (id == 'A') return gateA.future;
        return true;
      },
    );

    await pump(tester, staging(journey(id: 'A')));
    await tester.pump();
    expect(joined, ['A']);

    // The user switches to B while A's join is still in flight.
    await pump(tester, staging(journey(id: 'B')));
    await tester.pumpAndSettle();
    expect(joined, ['A', 'B']);

    // A now fails, late. It must not report B as failed.
    gateA.complete(false);
    await tester.pumpAndSettle();
    expect(
      find.text('Not receiving live updates — you may miss the start.'),
      findsNothing,
      reason: "a late failure for A must not be attributed to B",
    );
  });
}
