import '../../../../core/common/result.dart';
import '../../domain/entities/race_route.dart';
import '../entities/place_search_result.dart';

abstract class MapRepository {
  Future<RaceRoute?> getMarathonRoute();
  Future<Result<List<PlaceSearchResult>>> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    String? regionCode,
  });
}
