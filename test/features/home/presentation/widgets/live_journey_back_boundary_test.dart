import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/widgets/live_journey_back_boundary.dart';

/// Platform Back at the Home/live boundary, driven through the real
/// [PopScope] inside a real [Navigator].
///
/// The previous proof tapped a `ConvoyStatusBar` constructed with test-only
/// callbacks and separately grepped Home's source for a callback name. Neither
/// could see the actual defect: Home stopped intercepting Back once the chrome
/// was collapsed, so a *second* system Back popped the shell while the journey
/// was still running.
void main() {
  /// Dispatch a platform back gesture the way the OS does.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  /// Hosts the boundary one route deep, so a pop has somewhere to go — the
  /// bug is invisible if the boundary is the root route.
  Future<_Harness> pumpBoundary(
    WidgetTester tester, {
    required bool hasActiveJourney,
  }) async {
    final harness = _Harness(hasActiveJourney: hasActiveJourney);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StatefulBuilder(
                      builder: (context, setState) {
                        harness.rebuild = () => setState(() {});
                        return LiveJourneyBackBoundary(
                          hasActiveJourney: harness.hasActiveJourney,
                          isChromeCollapsed: harness.isCollapsed,
                          onCollapseChrome: harness.collapse,
                          onRestoreChrome: harness.restore,
                          child: const Scaffold(
                            body: Center(child: Text('journey chrome')),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                child: const Text('enter'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('enter'));
    await tester.pumpAndSettle();
    expect(find.text('journey chrome'), findsOneWidget);
    return harness;
  }

  testWidgets('first Back collapses the chrome and keeps the journey', (
    tester,
  ) async {
    final harness = await pumpBoundary(tester, hasActiveJourney: true);

    await pressBack(tester);

    expect(harness.collapses, 1);
    expect(harness.restores, 0);
    expect(
      find.text('journey chrome'),
      findsOneWidget,
      reason: 'the route must not pop — the journey is still running',
    );
  });

  testWidgets('a second Back while collapsed does not pop the shell', (
    tester,
  ) async {
    // The shipped bug: the intercept was released on collapse, so this second
    // Back tore the user off a running convoy with no way back to it.
    final harness = await pumpBoundary(tester, hasActiveJourney: true);

    await pressBack(tester);
    await pressBack(tester);

    expect(harness.collapses, 1);
    expect(
      harness.restores,
      1,
      reason: 'Back while collapsed restores the chrome instead of exiting',
    );
    expect(
      find.text('journey chrome'),
      findsOneWidget,
      reason: 'leaving a live journey must stay an explicit, confirmed action',
    );
  });

  testWidgets('Back keeps cycling rather than ever exiting the journey', (
    tester,
  ) async {
    final harness = await pumpBoundary(tester, hasActiveJourney: true);

    for (var i = 0; i < 6; i++) {
      await pressBack(tester);
    }

    expect(harness.collapses, 3);
    expect(harness.restores, 3);
    expect(find.text('journey chrome'), findsOneWidget);
  });

  testWidgets('with no active journey Back pops normally', (tester) async {
    final harness = await pumpBoundary(tester, hasActiveJourney: false);

    await pressBack(tester);

    expect(harness.collapses, 0);
    expect(harness.restores, 0);
    expect(
      find.text('journey chrome'),
      findsNothing,
      reason: 'the boundary must not trap the user when nothing is running',
    );
  });
}

class _Harness {
  _Harness({required this.hasActiveJourney});

  final bool hasActiveJourney;
  bool isCollapsed = false;
  int collapses = 0;
  int restores = 0;
  VoidCallback rebuild = () {};

  void collapse() {
    collapses++;
    isCollapsed = true;
    rebuild();
  }

  void restore() {
    restores++;
    isCollapsed = false;
    rebuild();
  }
}
