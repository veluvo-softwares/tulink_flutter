import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/widgets/pending_journey_overlay.dart';

/// `waitingForLeader` must be a real experience over the persistent map, not a
/// derived enum with no UI. These tests pin what a waiting member actually sees
/// and what they can do — including that they are never offered a Start button
/// that is not theirs to press.
void main() {
  Journey journey({
    JourneyStatus status = JourneyStatus.PENDING,
    List<Participant>? participants,
    String? inviteCode,
  }) => Journey(
    id: 'j1',
    inviteCode: inviteCode,
    name: 'Trip to Karen Shopping Centre',
    leaderId: 'leader-1',
    status: status,
    destination: const LatLng(latitude: -1.3234931, longitude: 36.7083102),
    destinationName: 'Karen Shopping Centre',
    destinationAddress: 'Nairobi, Kenya',
    lagThresholdMeters: 500,
    participants: participants,
  );

  Participant person(String id, String name, {String status = 'ACCEPTED'}) =>
      Participant(
        id: 'p-$id',
        userId: id,
        journeyId: 'j1',
        role: id == 'leader-1' ? 'LEADER' : 'MEMBER',
        status: status,
        displayName: name,
      );

  Future<void> pump(WidgetTester tester, Widget overlay) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.tulinkTheme,
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black12)),
            overlay,
          ],
        ),
      ),
    ),
  );

  Future<void> expandSheet(WidgetTester tester) async {
    await tester.drag(
      find.byType(DraggableScrollableSheet),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
  }

  group('an invited member waiting for the leader', () {
    testWidgets('names who the convoy is waiting on', (tester) async {
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: false,
          leaderName: 'Wanjiru',
          onDismiss: () {},
        ),
      );

      expect(
        find.textContaining('Waiting for Wanjiru'),
        findsOneWidget,
        reason: 'an unexplained wait reads as the app being stuck',
      );
      expect(find.text('WAITING'), findsOneWidget);
    });

    testWidgets('falls back gracefully when the leader is unknown', (
      tester,
    ) async {
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: false,
          onDismiss: () {},
        ),
      );

      expect(find.textContaining('Waiting for the leader'), findsOneWidget);
    });

    testWidgets('shows the destination the convoy is heading to', (
      tester,
    ) async {
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: false,
          onDismiss: () {},
        ),
      );

      expect(find.text('Karen Shopping Centre'), findsOneWidget);
      expect(find.text('Nairobi, Kenya'), findsOneWidget);
    });

    testWidgets('is never offered a Start it cannot press', (tester) async {
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: false,
          onDismiss: () {},
          // Even if a caller wrongly supplies these, a member must not see them.
          onStart: () {},
          onCancelJourney: () {},
        ),
      );

      expect(find.text('Start journey'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('can leave, and can step back to the map', (tester) async {
      var left = 0;
      var dismissed = 0;
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: false,
          onDismiss: () => dismissed++,
          onLeaveJourney: () => left++,
        ),
      );

      await expandSheet(tester);
      await tester.tap(find.text('Leave'));
      await tester.pump();
      expect(left, 1);

      await tester.tap(find.text('Browse map'));
      await tester.pump();
      expect(dismissed, 1);
    });

    testWidgets('surfaces a location failure without blocking membership', (
      tester,
    ) async {
      var retried = 0;
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: false,
          onDismiss: () {},
          onLeaveJourney: () {},
          locationFailure: const ConvoyFailure(
            message: 'Location permission denied',
          ),
          onRetryLocation: () => retried++,
        ),
      );

      await expandSheet(tester);
      // Denial is reported, and the member is still in the convoy: the waiting
      // chrome and Leave action remain, exactly per the Phase 1 invariant.
      expect(find.text('Location permission denied'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });
  });

  group('the leader staging their own journey', () {
    testWidgets('can start, share and cancel', (tester) async {
      var started = 0;
      var shared = 0;
      var cancelled = 0;
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(inviteCode: 'ABC123'),
          isLeader: true,
          onDismiss: () {},
          onStart: () => started++,
          onShareCode: () => shared++,
          onCancelJourney: () => cancelled++,
        ),
      );

      await expandSheet(tester);
      await tester.tap(find.text('Start journey'));
      await tester.pump();
      await tester.tap(find.text('Share code'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect([started, shared, cancelled], [1, 1, 1]);
    });

    testWidgets('actions are disabled while an action is in flight', (
      tester,
    ) async {
      var started = 0;
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(),
          isLeader: true,
          isBusy: true,
          onDismiss: () {},
          onStart: () => started++,
        ),
      );

      // A second Start would create a duplicate activation.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(started, 0);
    });
  });

  group('convoy membership', () {
    testWidgets('lists participants and marks the leader', (tester) async {
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(
            participants: [
              person('leader-1', 'Wanjiru'),
              person('u2', 'Otieno', status: 'INVITED'),
            ],
          ),
          isLeader: false,
          onDismiss: () {},
        ),
      );

      expect(find.text('Wanjiru'), findsOneWidget);
      expect(find.text('LEADER'), findsOneWidget);
      expect(find.text('Otieno'), findsOneWidget);
      expect(
        find.text('INVITED'),
        findsOneWidget,
        reason: 'an outstanding invite must be visibly different from a join',
      );
    });

    testWidgets('excludes people who left', (tester) async {
      await pump(
        tester,
        PendingJourneyOverlay(
          journey: journey(
            participants: [
              person('leader-1', 'Wanjiru'),
              person('u3', 'Achieng', status: 'LEFT'),
            ],
          ),
          isLeader: false,
          onDismiss: () {},
        ),
      );

      expect(find.text('Achieng'), findsNothing);
      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'convoy count excludes them',
      );
    });
  });
}
