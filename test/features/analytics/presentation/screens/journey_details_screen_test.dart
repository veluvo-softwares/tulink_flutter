import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/analytics/presentation/screens/journey_details_screen.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

void main() {
  const journey = Journey(
    id: 'journey-1',
    name: 'Laikipia patrol',
    leaderId: 'leader-1',
    status: JourneyStatus.CANCELLED,
    destination: LatLng(latitude: 0.0236, longitude: 37.9062),
    destinationName: 'Laikipia',
    destinationAddress: 'Laikipia County, Kenya',
    lagThresholdMeters: 500,
  );

  testWidgets('keeps the portrait recap treatment in tablet landscape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 1024);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.tulinkTheme,
        home: const JourneyDetailsScreen(journey: journey),
      ),
    );
    await tester.pump();

    final panel = tester.getRect(find.byKey(const Key('journey-recap-panel')));
    expect(panel.left, 299);
    expect(panel.top, 0);
    expect(panel.width, 768);
    expect(panel.height, 1024);
  });
}
