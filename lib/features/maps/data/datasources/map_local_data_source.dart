import '../models/race_route_model.dart';

abstract class MapLocalDataSource {
  Future<RaceRouteModel?> loadMarathonRoute();
}

class MapLocalDataSourceImpl implements MapLocalDataSource {
  @override
  Future<RaceRouteModel?> loadMarathonRoute() async {
    return null;
  }
}
