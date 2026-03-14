import '../../domain/entities/race_route.dart';

abstract class MapRepository {
  Future<RaceRoute?> getMarathonRoute();
}
