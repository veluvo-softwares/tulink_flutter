import '../../domain/entities/journey.dart';

abstract class JourneyLocalDataSource {
  Future<List<Journey>> getRecentJourneys();
}

class JourneyLocalDataSourceImpl implements JourneyLocalDataSource {
  @override
  Future<List<Journey>> getRecentJourneys() async {
    // Mock data for now - usually this would read from Hive or SQLite
    await Future.delayed(const Duration(milliseconds: 800)); // Simulate IO
    
    return [
      Journey(
        id: '1',
        origin: 'Miami',
        destination: 'Orlando',
        date: DateTime(2024, 1, 15),
        memberCount: 4,
        status: 'ACTIVE',
      ),
      Journey(
        id: '2',
        origin: 'Rio',
        destination: 'Sao Paulo',
        date: DateTime(2024, 1, 12),
        memberCount: 12,
        status: 'COMPLETED',
      ),
      Journey(
        id: '3',
        origin: 'Tokyo',
        destination: 'Kyoto',
        date: DateTime(2024, 1, 10),
        memberCount: 2,
        status: 'COMPLETED',
      ),
      Journey(
        id: '4',
        origin: 'Nairobi',
        destination: 'Mombasa',
        date: DateTime(2024, 1, 8),
        memberCount: 8,
        status: 'COMPLETED',
      ),
      // Extra one to test limiting to 4
      Journey(
        id: '5',
        origin: 'London',
        destination: 'Manchester',
        date: DateTime(2024, 1, 5),
        memberCount: 3,
        status: 'COMPLETED',
      ),
    ];
  }
}