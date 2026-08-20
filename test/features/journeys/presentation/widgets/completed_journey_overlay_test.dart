import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/presentation/widgets/completed_journey_overlay.dart';

/// Completion is rendered over the map the journey was driven on, instead of
/// pushing a details screen. These tests pin that: the overlay must be
/// dismissible and must never navigate on its own.
void main() {
  Journey journey() => Journey(
    id: 'j1',
    name: 'Trip to Karen Shopping Centre',
    leaderId: 'leader-1',
    status: JourneyStatus.COMPLETED,
    destination: const LatLng(latitude: -1.3234931, longitude: 36.7083102),
    destinationName: 'Karen Shopping Centre',
    destinationAddress: 'Nairobi, Kenya',
    lagThresholdMeters: 500,
  );

  Future<void> pump(
    WidgetTester tester, {
    required VoidCallback onDismiss,
    VoidCallback? onViewDetails,
    List<NavigatorObserver> observers = const [],
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.tulinkTheme,
        navigatorObservers: observers,
        home: Scaffold(
          body: Stack(
            children: [
              // Stands in for the persistent map underneath.
              const Positioned.fill(child: ColoredBox(color: Colors.black12)),
              CompletedJourneyOverlay(
                journey: journey(),
                onDismiss: onDismiss,
                onViewDetails: onViewDetails,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('summarises the journey that just finished', (tester) async {
    await pump(tester, onDismiss: () {});

    expect(find.text('Journey complete'), findsOneWidget);
    expect(
      find.text('Karen Shopping Centre'),
      findsOneWidget,
      reason: 'the recognisable place name leads, not the coarse address',
    );
    expect(find.text('Nairobi, Kenya'), findsOneWidget);
  });

  testWidgets('renders as an overlay without navigating', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await pump(tester, onDismiss: () {}, observers: [observer]);

    expect(
      observer.pushes,
      isEmpty,
      reason:
          'completion must not replace the map route — the route just driven '
          'stays visible behind the summary',
    );
    // The map placeholder is still in the tree beneath the overlay.
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('Done clears the completion state', (tester) async {
    var dismissed = 0;
    await pump(tester, onDismiss: () => dismissed++);

    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(dismissed, 1);
  });

  testWidgets('tapping the scrim also dismisses', (tester) async {
    var dismissed = 0;
    await pump(tester, onDismiss: () => dismissed++);

    // Top-left corner is scrim, well clear of the bottom card.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();

    expect(
      dismissed,
      1,
      reason: 'the user must never be trapped on a map they cannot use',
    );
  });

  testWidgets('details are offered but not forced', (tester) async {
    var viewed = 0;
    await pump(tester, onDismiss: () {}, onViewDetails: () => viewed++);

    await tester.tap(find.text('View details'));
    await tester.pump();

    expect(viewed, 1);
  });

  testWidgets('omits the details action when there is none', (tester) async {
    await pump(tester, onDismiss: () {});

    expect(find.text('View details'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The initial home route is not a navigation the overlay caused.
    if (previousRoute != null) pushes.add(route);
    super.didPush(route, previousRoute);
  }
}
