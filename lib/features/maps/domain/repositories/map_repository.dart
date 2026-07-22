import '../../../../core/common/result.dart';
import '../../domain/entities/race_route.dart';
import '../entities/place_search_result.dart';
import '../../data/models/route_result_model.dart';

abstract class MapRepository {
  Future<RaceRoute?> getMarathonRoute();
  Future<Result<List<PlaceSearchResult>>> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    String? regionCode,
  });

  Future<RouteResultModel?> getRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  });
}
