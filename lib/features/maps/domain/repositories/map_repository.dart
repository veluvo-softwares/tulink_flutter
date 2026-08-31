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

  /// Current server-owned route shared by every member of [journeyId].
  Future<RouteResultModel?> getCanonicalRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  });

  /// Asks the server to calculate and commit the next canonical route.
  Future<RouteResultModel?> replaceCanonicalRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required int baseVersion,
    required String reason,
  });

  /// The route already stored for this journey, if one matches the
  /// destination.
  ///
  /// Separate from [getRoute] because a Future resolves once and so cannot
  /// both draw immediately and refresh afterwards. Takes no origin: a stored
  /// route is keyed by journey and validated against its destination, and the
  /// caller may not have a GPS fix yet — which is precisely the moment this
  /// is worth reading.
  Future<RouteResultModel?> getCachedRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  });
}
