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
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
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
            timestamp: DateTime.now().millisecondsSinceEpoch,
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
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
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
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
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
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId1: MemberPosition(
            userId: otherUserId1,
            latitude: 2.0,
            longitude: 2.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            accuracy: 5.0,
            isMoving: true,
          ),
          otherUserId2: MemberPosition(
            userId: otherUserId2,
            latitude: 3.0,
            longitude: 3.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
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

  group('ConvoyProvider Formatters', () {
    late ConvoyProvider provider;
    late MockStreamConvoyPositions mockStreamConvoyPositions;
    late MockPublishMyPosition mockPublishMyPosition;
    late MockFetchLatestSnapshot mockFetchLatestSnapshot;
    late MockConvoyRepository mockRepository;

    setUp(() {
      mockStreamConvoyPositions = MockStreamConvoyPositions();
      mockPublishMyPosition = MockPublishMyPosition();
      mockFetchLatestSnapshot = MockFetchLatestSnapshot();
      mockRepository = MockConvoyRepository();
      
      provider = ConvoyProvider(
        streamConvoyPositions: mockStreamConvoyPositions,
        publishMyPosition: mockPublishMyPosition,
        fetchLatestSnapshot: mockFetchLatestSnapshot,
        repository: mockRepository,
      );
    });

    group('formatJourneyDuration', () {
      test('returns 0m when journey start time is null', () {
        expect(provider.formatJourneyDuration(), '0m');
      });

      test('returns 0m when end time is before or equal to start time', () {
        final start = DateTime(2023, 1, 1, 12, 0, 0);
        final end = DateTime(2023, 1, 1, 11, 59, 0); // Before start
        
        // Create test provider with mocked start time
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        testProvider.setJourneyStartTimeForTesting(start);
        
        expect(testProvider.formatJourneyDuration(end), '0m');
        expect(testProvider.formatJourneyDuration(start), '0m'); // Equal
      });

      test('formats sub-hour durations as "Xm"', () {
        final start = DateTime(2023, 1, 1, 12, 0, 0);
        final end = DateTime(2023, 1, 1, 12, 30, 0); // 30 minutes later
        
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        testProvider.setJourneyStartTimeForTesting(start);
        
        expect(testProvider.formatJourneyDuration(end), '30m');
      });

      test('formats multi-hour durations as "Xh Ym"', () {
        final start = DateTime(2023, 1, 1, 12, 0, 0);
        final end = DateTime(2023, 1, 1, 14, 15, 0); // 2h 15m later
        
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        testProvider.setJourneyStartTimeForTesting(start);
        
        expect(testProvider.formatJourneyDuration(end), '2h 15m');
      });

      test('handles 24+ hour journeys correctly', () {
        final start = DateTime(2023, 1, 1, 12, 0, 0);
        final end = DateTime(2023, 1, 2, 14, 30, 0); // 26h 30m later
        
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        testProvider.setJourneyStartTimeForTesting(start);
        
        expect(testProvider.formatJourneyDuration(end), '26h 30m');
      });
    });

    group('formatJourneyDistance', () {
      test('formats sub-km distances in meters', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setDistanceTraveledForTesting(35.0);
        expect(testProvider.formatJourneyDistance(), '35 m');
        
        testProvider.setDistanceTraveledForTesting(999.0);
        expect(testProvider.formatJourneyDistance(), '999 m');
      });

      test('formats 1-10 km with 2 decimals', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setDistanceTraveledForTesting(1500.0); // 1.5 km
        expect(testProvider.formatJourneyDistance(), '1.50 km');
        
        testProvider.setDistanceTraveledForTesting(5750.0); // 5.75 km
        expect(testProvider.formatJourneyDistance(), '5.75 km');
      });

      test('formats 10+ km with 1 decimal', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setDistanceTraveledForTesting(12750.0); // 12.75 km
        expect(testProvider.formatJourneyDistance(), '12.8 km');
        
        testProvider.setDistanceTraveledForTesting(45000.0); // 45 km
        expect(testProvider.formatJourneyDistance(), '45.0 km');
      });

      test('handles negative input as 0 m', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setDistanceTraveledForTesting(-100.0);
        expect(testProvider.formatJourneyDistance(), '0 m');
      });
    });

    group('formatJourneyPace', () {
      test('returns -- for distances under threshold', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setJourneyStartTimeForTesting(DateTime.now().subtract(Duration(minutes: 5)));
        testProvider.setDistanceTraveledForTesting(30.0); // Under 50m threshold
        
        expect(testProvider.formatJourneyPace(), '--');
      });

      test('returns -- for zero or negative duration', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setJourneyStartTimeForTesting(DateTime.now().add(Duration(minutes: 5))); // Future start
        testProvider.setDistanceTraveledForTesting(1000.0);
        
        expect(testProvider.formatJourneyPace(), '--');
      });

      test('formats a normal walking pace correctly', () {
        final start = DateTime.now().subtract(Duration(minutes: 20)); // 20 minutes ago
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setJourneyStartTimeForTesting(start);
        testProvider.setDistanceTraveledForTesting(1000.0); // 1 km
        
        expect(testProvider.formatJourneyPace(), '20:00 /km'); // 20 min per km
      });

      test('formats a normal driving pace correctly', () {
        final start = DateTime.now().subtract(Duration(minutes: 2)); // 2 minutes ago  
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setJourneyStartTimeForTesting(start);
        testProvider.setDistanceTraveledForTesting(1500.0); // 1.5 km
        
        expect(testProvider.formatJourneyPace(), '1:20 /km'); // 1:20 per km (fast pace)
      });

      test('handles infinite/NaN gracefully', () {
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setJourneyStartTimeForTesting(DateTime.now().subtract(Duration(hours: 2)));
        testProvider.setDistanceTraveledForTesting(0.0); // Zero distance
        
        expect(testProvider.formatJourneyPace(), '--');
      });

      test('handles very slow pace gracefully', () {
        final start = DateTime.now().subtract(Duration(hours: 2)); // 2 hours ago
        final testProvider = ConvoyProvider(
          streamConvoyPositions: mockStreamConvoyPositions,
          publishMyPosition: mockPublishMyPosition,
          fetchLatestSnapshot: mockFetchLatestSnapshot,
          repository: mockRepository,
        );
        
        testProvider.setJourneyStartTimeForTesting(start);
        testProvider.setDistanceTraveledForTesting(100.0); // 0.1 km in 2 hours (very slow)
        
        expect(testProvider.formatJourneyPace(), '--'); // Should return -- for unrealistic pace
      });
    });
  });
}