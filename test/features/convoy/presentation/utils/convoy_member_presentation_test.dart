import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/presentation/utils/convoy_member_presentation.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';

void main() {
  const journey = Journey(
    id: 'journey-1',
    name: 'Convoy',
    leaderId: 'leader',
    status: JourneyStatus.ACTIVE,
    destination: LatLng(latitude: -1.2, longitude: 36.8),
    destinationAddress: 'Nairobi',
    lagThresholdMeters: 500,
    participants: <Participant>[
      Participant(
        id: 'p2',
        userId: 'follower',
        journeyId: 'journey-1',
        role: 'FOLLOWER',
        status: 'ACTIVE',
        displayName: 'Wesley Muriithi',
      ),
      Participant(
        id: 'p1',
        userId: 'leader',
        journeyId: 'journey-1',
        role: 'LEADER',
        status: 'ACTIVE',
        displayName: 'Emma X',
      ),
    ],
  );

  test('uses display-name initials and assigns leader the first color', () {
    final identities = ConvoyMemberPresentation.forJourney(journey);

    expect(identities['follower']?.initials, 'WM');
    expect(identities['leader']?.initials, 'EX');
    expect(identities['leader']?.color, ConvoyMemberPresentation.palette.first);
  });

  test('identity assignment is stable regardless of participant order', () {
    final reversed = Journey(
      id: journey.id,
      name: journey.name,
      leaderId: journey.leaderId,
      status: journey.status,
      destination: journey.destination,
      destinationAddress: journey.destinationAddress,
      lagThresholdMeters: journey.lagThresholdMeters,
      participants: journey.participants!.reversed.toList(),
    );

    final first = ConvoyMemberPresentation.forJourney(journey);
    final second = ConvoyMemberPresentation.forJourney(reversed);

    expect(first['leader']?.color, second['leader']?.color);
    expect(first['follower']?.color, second['follower']?.color);
  });
}
