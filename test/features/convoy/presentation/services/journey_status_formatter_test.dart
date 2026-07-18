import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';
import 'package:tulink_flutter/features/convoy/presentation/services/journey_status_formatter.dart';

void main() {
  group('formatEta', () {
    test('clamps sub-minute to 1 min', () => expect(formatEta(20), '1 min'));
    test('minutes only', () => expect(formatEta(12 * 60), '12 min'));
    test('hours and minutes', () => expect(formatEta(65 * 60), '1 h 05 min'));
  });

  group('formatDistance', () {
    test('metres below 1 km', () => expect(formatDistance(850), '850 m'));
    test('kilometres above', () => expect(formatDistance(3421), '3.4 km'));
  });

  group('buildMemberLines', () {
    const destination = ConvoyDestination(latitude: 0, longitude: 0);

    MemberPosition member(
      String userId,
      double latitude, {
      String? statusChange,
    }) => MemberPosition(
      userId: userId,
      latitude: latitude,
      longitude: 0,
      timestamp: 1784284449569,
      statusChange: statusChange,
    );

    test('orders nearest first, arrived last, and skips self', () {
      final lines = buildMemberLines(
        members: {
          'me': member('me', 0.001),
          'far': member('far', 0.5),
          'near': member('near', 0.01),
          'done': member('done', 0.9, statusChange: 'ARRIVED'),
        },
        destination: destination,
        displayNames: const {
          'far': 'Farai',
          'near': 'Nia',
          'done': 'Dede',
          'me': 'Self',
        },
        selfUserId: 'me',
      );

      expect(lines, hasLength(3));
      expect(lines[0], startsWith('Nia — '));
      expect(lines[1], startsWith('Farai — '));
      expect(lines[2], 'Dede — arrived');
      expect(lines.join(), isNot(contains('Self')));
    });

    test('falls back to userId when no display name is known', () {
      final lines = buildMemberLines(
        members: {'u9': member('u9', 0.01)},
        destination: destination,
        displayNames: const {},
        selfUserId: 'me',
      );
      expect(lines.single, startsWith('u9 — '));
    });
  });

  group('buildStatusTitle', () {
    test('plain name without navigation data', () {
      expect(
        buildStatusTitle(
          journeyName: 'Coast run',
          etaSeconds: null,
          distanceRemainingMeters: null,
        ),
        'Coast run',
      );
    });

    test('appends ETA and distance when navigating', () {
      expect(
        buildStatusTitle(
          journeyName: 'Coast run',
          etaSeconds: 15 * 60,
          distanceRemainingMeters: 12400,
        ),
        'Coast run — 15 min · 12.4 km',
      );
    });
  });
}
