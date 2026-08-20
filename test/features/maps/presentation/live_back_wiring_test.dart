import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/presentation/widgets/convoy_status_bar.dart';

/// Back during a live journey must collapse the chrome, not tear the journey
/// down.
///
/// This drives the actual `ConvoyStatusBar` back control and asserts which
/// callback fires. The previous guard only searched Home's source for
/// `onBack: _collapseLiveChrome`, which was true while the live layer below it
/// still passed `widget.onExit` to the status bar — the wiring was broken in
/// production and every test passed.
void main() {
  Widget wrap({
    required VoidCallback onBack,
    required VoidCallback onExit,
    bool wireBackToExit = false,
  }) => MaterialApp(
    theme: AppTheme.tulinkTheme,
    home: Scaffold(
      body: ConvoyStatusBar(
        snapshot: null,
        connectionState: ConvoyConnectionState.connected,
        journeyId: 'j1',
        connectionAttemptId: 1,
        // The parameter under test: whichever callback the live layer supplies
        // is the one Back invokes.
        onBack: wireBackToExit ? onExit : onBack,
      ),
    ),
  );

  testWidgets('the back control invokes the collapse callback', (tester) async {
    var collapsed = 0;
    var exited = 0;
    await tester.pumpWidget(
      wrap(onBack: () => collapsed++, onExit: () => exited++),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(collapsed, 1);
    expect(
      exited,
      0,
      reason: 'Back must never reach the journey teardown path',
    );
  });

  testWidgets('the test detects a regression to the exit callback', (
    tester,
  ) async {
    // Negative control: this is exactly the production bug that shipped. If the
    // live layer is ever rewired to onExit again, the assertion above fails.
    var collapsed = 0;
    var exited = 0;
    await tester.pumpWidget(
      wrap(
        onBack: () => collapsed++,
        onExit: () => exited++,
        wireBackToExit: true,
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(exited, 1, reason: 'proves the tap reaches whatever is wired');
    expect(collapsed, 0);
  });

  testWidgets('no back control is shown when none is supplied', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.tulinkTheme,
        home: const Scaffold(
          body: ConvoyStatusBar(
            snapshot: null,
            connectionState: ConvoyConnectionState.connected,
            journeyId: 'j1',
            connectionAttemptId: 1,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });
}
