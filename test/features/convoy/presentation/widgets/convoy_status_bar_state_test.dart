import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/presentation/widgets/convoy_status_bar.dart';

/// The status bar used to render the literal string "CONNECTING..." whenever
/// the snapshot was null — with no timeout and no error branch — so any failure
/// to receive a snapshot was presented indefinitely as benign progress, even
/// while the socket was genuinely connected.
void main() {
  Widget wrap({
    ConvoySnapshot? snapshot,
    ConvoyConnectionState connectionState = ConvoyConnectionState.connecting,
    Failure? locationFailure,
    VoidCallback? onRetryLocation,
    String? journeyId,
    int connectionAttemptId = 0,
    VoidCallback? onReconnect,
    bool isReconnecting = false,
  }) {
    return MaterialApp(
      theme: AppTheme.tulinkTheme,
      home: Scaffold(
        body: ConvoyStatusBar(
          snapshot: snapshot,
          connectionState: connectionState,
          locationFailure: locationFailure,
          onRetryLocation: onRetryLocation,
          journeyId: journeyId,
          connectionAttemptId: connectionAttemptId,
          onReconnect: onReconnect,
          isReconnecting: isReconnecting,
        ),
      ),
    );
  }

  ConvoySnapshot buildSnapshot() => ConvoySnapshot(
    journeyId: 'j1',
    members: const {},
    destination: const ConvoyDestination(latitude: -1.32, longitude: 36.70),
    destinationAddress: 'Nairobi, Kenya',
    timestamp: DateTime.utc(2026, 8, 15),
  );

  group('connection status text', () {
    testWidgets('shows CONNECTING during the grace period', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.text('CONNECTING...'), findsOneWidget);
      expect(find.text('NOT CONNECTED'), findsNothing);
    });

    testWidgets('stops claiming progress once the grace period lapses', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('CONNECTING...'), findsOneWidget);

      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );

      expect(
        find.text('CONNECTING...'),
        findsNothing,
        reason: 'an unbounded "connecting" state is unactionable for the user',
      );
      expect(find.text('NOT CONNECTED'), findsOneWidget);
    });

    testWidgets('reports a connection error immediately', (tester) async {
      await tester.pumpWidget(
        wrap(connectionState: ConvoyConnectionState.error),
      );
      await tester.pump();

      expect(find.text('CONNECTION ERROR'), findsOneWidget);
      expect(find.text('CONNECTING...'), findsNothing);
    });

    testWidgets('connecting WITH a retained snapshot is treated as stale', (
      tester,
    ) async {
      // A snapshot held while the socket is still coming up describes the
      // convoy as it was, not as it is.
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.connecting,
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('SOLO JOURNEY'), findsNothing);
      expect(find.text('CONNECTING...'), findsOneWidget);
      expect(find.textContaining('Last known:'), findsOneWidget);
    });

    testWidgets('connecting with a retained snapshot still times out', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.connecting,
          onReconnect: () {},
        ),
      );
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );

      expect(find.text('NOT CONNECTED'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('a connected socket with no snapshot still times out', (
      tester,
    ) async {
      // The exact situation observed in the field: connectionState was
      // `connected` while the bar insisted it was connecting.
      await tester.pumpWidget(
        wrap(connectionState: ConvoyConnectionState.connected),
      );
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );

      expect(find.text('NOT CONNECTED'), findsOneWidget);
    });
  });

  group('location status is independent of convoy connectivity', () {
    testWidgets('surfaces a location failure on its own line', (tester) async {
      await tester.pumpWidget(
        wrap(locationFailure: ConvoyFailure.locationUnavailable),
      );
      await tester.pump();

      expect(
        find.text(ConvoyFailure.locationUnavailable.message),
        findsOneWidget,
      );
    });

    testWidgets('offers a retry affordance when a handler is provided', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        wrap(
          locationFailure: ConvoyFailure.locationUnavailable,
          onRetryLocation: () => retries++,
        ),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('shows no location line when location is healthy', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.location_disabled), findsNothing);
    });
  });

  group('watchdog lifecycle', () {
    testWidgets(
      'null -> received -> cancelled -> lost -> new grace -> NOT CONNECTED',
      (tester) async {
        // 1. No snapshot: the grace period is running.
        await tester.pumpWidget(wrap(journeyId: 'j1'));
        await tester.pump();
        expect(find.text('CONNECTING...'), findsOneWidget);

        // 2. Snapshot arrives on a connected socket, well inside the grace
        //    period. Only `connected` establishes liveness.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(
          wrap(
            journeyId: 'j1',
            snapshot: buildSnapshot(),
            connectionState: ConvoyConnectionState.connected,
          ),
        );
        await tester.pump();
        expect(find.text('CONNECTING...'), findsNothing);
        expect(find.text('NOT CONNECTED'), findsNothing);

        // 3. The old timer must have been cancelled: pushing past the original
        //    deadline while connected must not flip us to a failure state.
        await tester.pump(
          ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
        );
        expect(find.text('NOT CONNECTED'), findsNothing);

        // 4. Snapshot is lost — a NEW grace period must begin.
        await tester.pumpWidget(wrap(journeyId: 'j1'));
        await tester.pump();
        expect(
          find.text('CONNECTING...'),
          findsOneWidget,
          reason: 'losing a snapshot restarts the wait, it does not hang',
        );

        // 5. That new grace period expires.
        await tester.pump(
          ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
        );
        expect(find.text('NOT CONNECTED'), findsOneWidget);
      },
    );

    testWidgets('a new journey id resets a timed-out state', (tester) async {
      await tester.pumpWidget(wrap(journeyId: 'j1'));
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );
      expect(find.text('NOT CONNECTED'), findsOneWidget);

      // Switching journeys is a fresh connection attempt.
      await tester.pumpWidget(wrap(journeyId: 'j2'));
      await tester.pump();
      expect(find.text('CONNECTING...'), findsOneWidget);
      expect(find.text('NOT CONNECTED'), findsNothing);
    });

    testWidgets('an error state does not keep counting down', (tester) async {
      await tester.pumpWidget(
        wrap(journeyId: 'j1', connectionState: ConvoyConnectionState.error),
      );
      await tester.pump();
      expect(find.text('CONNECTION ERROR'), findsOneWidget);

      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );
      // Still the more specific message, not the weaker timeout one.
      expect(find.text('CONNECTION ERROR'), findsOneWidget);
      expect(find.text('NOT CONNECTED'), findsNothing);
    });
  });

  group('convoy reconnect action', () {
    testWidgets('is offered once the grace period lapses', (tester) async {
      await tester.pumpWidget(wrap(journeyId: 'j1', onReconnect: () {}));
      await tester.pump();
      expect(find.text('Reconnect'), findsNothing);

      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('is offered immediately on a connection error', (tester) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionState: ConvoyConnectionState.error,
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('is independent of the location retry action', (tester) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionState: ConvoyConnectionState.error,
          onReconnect: () {},
          locationFailure: ConvoyFailure.locationUnavailable,
          onRetryLocation: () {},
        ),
      );
      await tester.pump();

      // Two distinct affordances for two independent failures.
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('invokes the handler and has button semantics', (tester) async {
      var reconnects = 0;
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionState: ConvoyConnectionState.error,
          onReconnect: () => reconnects++,
        ),
      );
      await tester.pump();

      final semantics = tester.getSemantics(find.text('Reconnect'));
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(semantics.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(semantics.label, 'Reconnect');

      // Adequate touch target (>= 44pt tall).
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44.0),
      );

      await tester.tap(find.text('Reconnect'));
      await tester.pump();
      expect(reconnects, 1);
    });

    testWidgets('refuses concurrent attempts while in flight', (tester) async {
      var reconnects = 0;
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionState: ConvoyConnectionState.error,
          onReconnect: () => reconnects++,
          isReconnecting: true,
        ),
      );
      await tester.pump();

      // Progress is shown and the control is inert.
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Reconnecting'), warnIfMissed: false);
      await tester.pump();
      expect(reconnects, 0);
    });

    testWidgets('is hidden once a LIVE snapshot arrives', (tester) async {
      // A snapshot only hides the action when the connection is actually
      // healthy. Snapshot + error is the stale case, and must keep offering
      // recovery — see the "connection state overrides a stale snapshot" group.
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionState: ConvoyConnectionState.connected,
          onReconnect: () {},
          snapshot: buildSnapshot(),
        ),
      );
      await tester.pump();

      expect(find.text('Reconnect'), findsNothing);
    });
  });

  group('connection state overrides a stale snapshot', () {
    testWidgets('error + snapshot shows CONNECTION ERROR, not convoy status', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.error,
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('CONNECTION ERROR'), findsOneWidget);
      // A dead socket must never render its last snapshot as live status.
      expect(find.text('SOLO JOURNEY'), findsNothing);
      expect(find.text('CONVOY READY'), findsNothing);
      expect(find.text('IN PROGRESS'), findsNothing);
      // And the recovery action must be reachable.
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('reconnecting + snapshot shows RECONNECTING...', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.reconnecting,
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('RECONNECTING...'), findsOneWidget);
      expect(find.text('SOLO JOURNEY'), findsNothing);
    });

    testWidgets('disconnected + snapshot is not proof of connectivity', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.disconnected,
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('SOLO JOURNEY'), findsNothing);
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('stale membership is labelled as last known', (tester) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.error,
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Last known:'),
        findsOneWidget,
        reason: 'stale context is fine, but it must be marked stale',
      );
    });

    testWidgets('connected + snapshot shows normal convoy status', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          snapshot: buildSnapshot(),
          connectionState: ConvoyConnectionState.connected,
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('CONNECTION ERROR'), findsNothing);
      expect(find.text('RECONNECTING...'), findsNothing);
      expect(find.text('CONNECTING...'), findsNothing);
      // Healthy: no recovery affordance needed.
      expect(find.text('Reconnect'), findsNothing);
      expect(find.textContaining('Last known:'), findsNothing);
    });
  });

  group('same-journey reconnect attempts', () {
    testWidgets('a new attempt clears a previous timeout', (tester) async {
      await tester.pumpWidget(wrap(journeyId: 'j1', connectionAttemptId: 1));
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );
      expect(find.text('NOT CONNECTED'), findsOneWidget);

      // Same journey, new attempt — must not inherit the old timeout.
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionAttemptId: 2,
          connectionState: ConvoyConnectionState.reconnecting,
        ),
      );
      await tester.pump();

      expect(find.text('NOT CONNECTED'), findsNothing);
      expect(find.text('RECONNECTING...'), findsOneWidget);
    });

    testWidgets('a plain rebuild does not restart the countdown', (
      tester,
    ) async {
      // Now that the status bar lives inside the persistent Home shell it is
      // rebuilt by unrelated state changes — a convoy snapshot, a tab switch,
      // a provider notify. Only a genuinely new attempt may clear the timeout;
      // if an ordinary rebuild reset it, the bar would sit on CONNECTING
      // forever and never offer Reconnect.
      await tester.pumpWidget(wrap(journeyId: 'j1', connectionAttemptId: 7));
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );
      expect(find.text('NOT CONNECTED'), findsOneWidget);

      // Same journey, same attempt — rebuilt for an unrelated reason.
      await tester.pumpWidget(wrap(journeyId: 'j1', connectionAttemptId: 7));
      await tester.pump();

      expect(
        find.text('NOT CONNECTED'),
        findsOneWidget,
        reason: 'the timeout belongs to the attempt, not to the widget build',
      );
      expect(find.text('CONNECTING...'), findsNothing);
    });

    testWidgets('a failed reconnect returns to an actionable state', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionAttemptId: 2,
          connectionState: ConvoyConnectionState.reconnecting,
          onReconnect: () {},
        ),
      );
      await tester.pump();
      expect(find.text('RECONNECTING...'), findsOneWidget);

      // The fresh window lapses with no snapshot.
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );

      expect(find.text('NOT CONNECTED'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('a fresh snapshot after reconnect restores normal status', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionAttemptId: 2,
          connectionState: ConvoyConnectionState.reconnecting,
          onReconnect: () {},
        ),
      );
      await tester.pump();
      expect(find.text('RECONNECTING...'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          journeyId: 'j1',
          connectionAttemptId: 2,
          connectionState: ConvoyConnectionState.connected,
          snapshot: buildSnapshot(),
          onReconnect: () {},
        ),
      );
      await tester.pump();

      expect(find.text('RECONNECTING...'), findsNothing);
      expect(find.text('NOT CONNECTED'), findsNothing);
      expect(find.text('Reconnect'), findsNothing);

      // And the restored status stays stable past the old deadline.
      await tester.pump(
        ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
      );
      expect(find.text('NOT CONNECTED'), findsNothing);
    });
  });

  testWidgets('cancels its watchdog on dispose', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    // Advancing past the grace period must not schedule work on a disposed
    // State; pumpAndSettle would surface a pending-timer assertion.
    await tester.pump(
      ConvoyStatusBar.connectingGracePeriod + const Duration(seconds: 1),
    );

    expect(tester.takeException(), isNull);
  });
}
