import '../../domain/entities/race_route.dart';
import '../../domain/repositories/map_repository.dart';
import '../datasources/map_local_data_source.dart';

class MapRepositoryImpl implements MapRepository {
  final MapLocalDataSource localDataSource;

  MapRepositoryImpl({required this.localDataSource});

  @override
  Future<RaceRoute?> getMarathonRoute() async {
    return await localDataSource.loadMarathonRoute();
  }
}
