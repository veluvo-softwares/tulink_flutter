import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/presentation/widgets/convoy_status_bar.dart';

/// What the visible status-bar Back control does.
///
/// Scope note: this file asserts only that the control exists and invokes the
/// callback it was given. It deliberately no longer contains a "negative
/// control" that wires the callback the other way and asserts that the other
/// callback fires — that proved nothing about production, because the test
/// itself chose the wiring.
///
/// The two things it cannot see are covered where they are actually decidable:
///
/// * *which* callback the live layer hands down — `single_map_invariant_test`,
///   a genuine cross-layer invariant no widget test can observe;
/// * what the **platform** Back gesture does at the Home/live boundary —
///   `live_journey_back_boundary_test`, which drives a real `PopScope` in a
///   real `Navigator`. That is where the shipped defect lived.
void main() {
  Widget wrap({required VoidCallback onBack}) => MaterialApp(
    theme: AppTheme.tulinkTheme,
    home: Scaffold(
      body: ConvoyStatusBar(
        snapshot: null,
        connectionState: ConvoyConnectionState.connected,
        journeyId: 'j1',
        connectionAttemptId: 1,
        onBack: onBack,
      ),
    ),
  );

  testWidgets('the back control invokes its callback', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(wrap(onBack: () => pressed++));

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(pressed, 1);
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
