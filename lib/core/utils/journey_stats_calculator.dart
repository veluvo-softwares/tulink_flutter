import '../../features/journeys/domain/entities/journey.dart';

/// Utility class for calculating journey-related statistics
class JourneyStatsCalculator {
  JourneyStatsCalculator._();

  /// Calculates the number of journeys where the user is the leader
  /// 
  /// [journeys] - List of all journeys
  /// [userId] - Current user's ID to compare against leaderId
  /// 
  /// Returns the count of journeys where leaderId matches userId
  static int calculateLeadershipCount(List<Journey> journeys, String userId) {
    if (journeys.isEmpty || userId.isEmpty) {
      return 0;
    }

    return journeys.where((journey) => journey.leaderId == userId).length;
  }

  /// Calculates total distance from completed journeys
  /// This can be expanded when journey analytics data becomes available
  /// 
  /// [journeys] - List of journeys to calculate distance from
  /// 
  /// Returns total distance in kilometers
  static double calculateTotalDistance(List<Journey> journeys) {
    // For now, this is a placeholder calculation
    // In the future, this would sum up actual distance data from journey analytics
    final completedJourneys = journeys.where(
      (journey) => journey.status == JourneyStatus.COMPLETED,
    ).length;
    
    // Mock calculation: assume average 5km per completed journey
    return completedJourneys * 5.0;
  }

  /// Calculates participation count (total journeys user has participated in)
  /// This includes both led journeys and journeys as a follower
  /// 
  /// [journeys] - List of journeys
  /// [userId] - Current user's ID
  /// 
  /// Returns total participation count
  static int calculateParticipationCount(List<Journey> journeys, String userId) {
    if (journeys.isEmpty || userId.isEmpty) {
      return journeys.length; // If no userId provided, return total count
    }

    return journeys.where((journey) {
      // Check if user is the leader
      if (journey.leaderId == userId) {
        return true;
      }
      
      // Check if user is in participants list
      if (journey.participants != null) {
        return journey.participants!.any(
          (participant) => participant.userId == userId,
        );
      }
      
      return false;
    }).length;
  }

  /// Formats distance value for display
  /// 
  /// [distance] - Distance value in kilometers
  /// 
  /// Returns formatted string representation
  static String formatDistance(double distance) {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}k';
    } else if (distance >= 10) {
      return distance.toStringAsFixed(0);
    } else {
      return distance.toStringAsFixed(1);
    }
  }
}