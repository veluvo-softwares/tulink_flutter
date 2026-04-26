import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/convoy_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/stream_convoy_positions.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/publish_my_position.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/fetch_latest_snapshot.dart';
import 'package:tulink_flutter/features/convoy/domain/repositories/convoy_repository.dart';

@GenerateMocks([StreamConvoyPositions, PublishMyPosition, FetchLatestSnapshot, ConvoyRepository])
import 'convoy_provider_test.mocks.dart';

void main() {
  group('ConvoyProvider - Self Filtering Tests', () {
    late ConvoyProvider convoyProvider;
    late MockStreamConvoyPositions mockStreamConvoyPositions;
    late MockPublishMyPosition mockPublishMyPosition;
    late MockFetchLatestSnapshot mockFetchLatestSnapshot;
    late MockConvoyRepository mockRepository;

    const currentUserId = 'user123';
    const otherUserId1 = 'user456';
    const otherUserId2 = 'user789';
    const journeyId = 'journey123';

    setUp(() {
      mockStreamConvoyPositions = MockStreamConvoyPositions();
      mockPublishMyPosition = MockPublishMyPosition();
      mockFetchLatestSnapshot = MockFetchLatestSnapshot();
      mockRepository = MockConvoyRepository();

      convoyProvider = ConvoyProvider(
        streamConvoyPositions: mockStreamConvoyPositions,
        publishMyPosition: mockPublishMyPosition,
        fetchLatestSnapshot: mockFetchLatestSnapshot,
        repository: mockRepository,
      );
    });

    group('getDisplaySnapshot', () {
      test('should exclude current user from display snapshot', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: false,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        // Set the snapshot directly for testing
        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final displaySnapshot = convoyProvider.getDisplaySnapshot(currentUserId);

        // Assert
        expect(displaySnapshot, isNotNull);
        expect(displaySnapshot!.members.length, equals(2));
        expect(displaySnapshot.members.containsKey(currentUserId), isFalse);
        expect(displaySnapshot.members.containsKey(otherUserId1), isTrue);
        expect(displaySnapshot.members.containsKey(otherUserId2), isTrue);
      });

      test('should return empty members map for solo journey with only current user', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final displaySnapshot = convoyProvider.getDisplaySnapshot(currentUserId);

        // Assert
        expect(displaySnapshot, isNotNull);
        expect(displaySnapshot!.members.length, equals(0));
        expect(displaySnapshot.members.containsKey(currentUserId), isFalse);
      });

      test('should return unchanged snapshot when current user not in members', () {
        // Arrange - Edge case: current user has not yet written to RTDB
        final memberPositions = {
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: false,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final displaySnapshot = convoyProvider.getDisplaySnapshot(currentUserId);

        // Assert
        expect(displaySnapshot, isNotNull);
        expect(displaySnapshot!.members.length, equals(2));
        expect(displaySnapshot.members.containsKey(currentUserId), isFalse);
        expect(displaySnapshot.members.containsKey(otherUserId1), isTrue);
        expect(displaySnapshot.members.containsKey(otherUserId2), isTrue);
      });

      test('should return null when no snapshot available', () {
        // Act
        final displaySnapshot = convoyProvider.getDisplaySnapshot(currentUserId);

        // Assert
        expect(displaySnapshot, isNull);
      });
    });

    group('getFullSnapshot', () {
      test('should return unfiltered snapshot including current user', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final fullSnapshot = convoyProvider.getFullSnapshot();

        // Assert
        expect(fullSnapshot, isNotNull);
        expect(fullSnapshot!.members.length, equals(2));
        expect(fullSnapshot.members.containsKey(currentUserId), isTrue);
        expect(fullSnapshot.members.containsKey(otherUserId1), isTrue);
      });
    });

    group('Member count consistency', () {
      test('display snapshot should have fewer members than full snapshot', () {
        // Arrange
        final memberPositions = {
          currentUserId: MemberPosition(
            userId: currentUserId,
            latitude: 1.0,
            longitude: 1.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            isMoving: false,
          ),
        };

        final snapshot = ConvoySnapshot(
          journeyId: journeyId,
          members: memberPositions,
          destination: const ConvoyDestination(latitude: 5.0, longitude: 5.0),
          destinationAddress: 'Test Destination',
          timestamp: DateTime.now(),
        );

        convoyProvider.setSnapshotForTesting(snapshot);

        // Act
        final fullSnapshot = convoyProvider.getFullSnapshot();
        final displaySnapshot = convoyProvider.getDisplaySnapshot(currentUserId);

        // Assert
        expect(fullSnapshot!.totalMembers, equals(3));
        expect(displaySnapshot!.totalMembers, equals(2));
        expect(fullSnapshot.totalMembers - displaySnapshot.totalMembers, equals(1));
      });
    });
  });
}

// Test helper method is now available directly on ConvoyProvider as setSnapshotForTesting()