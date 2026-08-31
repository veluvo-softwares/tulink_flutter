import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';
import 'package:tulink_flutter/features/convoy/presentation/widgets/journey_progress_card.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

void main() {
  testWidgets('tapping a member avatar selects that member directly', (
    tester,
  ) async {
    final member = MemberPosition(
      userId: 'member-1',
      latitude: -1.3,
      longitude: 36.8,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final snapshot = ConvoySnapshot(
      journeyId: 'journey-1',
      members: {'member-1': member},
      destination: const ConvoyDestination(latitude: -1.2, longitude: 36.9),
      destinationAddress: 'Karen',
    );
    const journey = Journey(
      id: 'journey-1',
      name: 'Trip to Karen',
      leaderId: 'leader-1',
      status: JourneyStatus.ACTIVE,
      destination: LatLng(latitude: -1.2, longitude: 36.9),
      destinationName: 'Karen',
      destinationAddress: 'Karen, Nairobi',
      lagThresholdMeters: 500,
      participants: [
        Participant(
          id: 'participant-1',
          userId: 'member-1',
          journeyId: 'journey-1',
          role: 'FOLLOWER',
          status: 'ACTIVE',
          displayName: 'Alice',
        ),
      ],
    );
    MemberPosition? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.tulinkTheme,
        home: Scaffold(
          body: JourneyProgressCard(
            journey: journey,
            convoySnapshot: snapshot,
            currentUserId: 'leader-1',
            isLeader: true,
            isExpanded: true,
            onMemberTap: (member) => selected = member,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('convoy-member-member-1')));
    expect(selected, same(member));
    expect(find.text('member-1'), findsNothing);
  });
}
