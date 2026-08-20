import '../../../../core/services/location_service.dart';
import '../../data/models/route_result_model.dart';

/// Where the live route geometry should come from.
///
/// Modelled explicitly so the *ordering* of the decision is testable on its
/// own: a cached route that already ends at the destination needs no origin,
/// so it must be chosen before any GPS work happens. Acquiring a position
/// first meant a device without a fix discarded a route it already had.
sealed class RouteSource {
  const RouteSource();
}

/// A previously fetched route already ends at this destination — draw it.
class CachedRouteSource extends RouteSource {
  const CachedRouteSource(this.route);

  final RouteResultModel route;
}

/// A fresh route must be requested from [originLat]/[originLng].
class FetchRouteSource extends RouteSource {
  const FetchRouteSource({required this.originLat, required this.originLng});

  final double originLat;
  final double originLng;
}

/// No usable cached route and no origin. The caller should keep the
/// destination visible and retry once a position arrives.
class AwaitingLocationRouteSource extends RouteSource {
  const AwaitingLocationRouteSource();
}

/// Tolerance for treating a route's final coordinate as "this destination".
/// Route providers snap the last point to the road network, so an exact match
/// is never expected.
const double kDestinationMatchToleranceDegrees = 0.001;

/// True when [coordinate] (`[lng, lat]`) is effectively the destination.
bool routeEndsAtDestination(
  List<double> coordinate,
  double destinationLng,
  double destinationLat,
) {
  if (coordinate.length < 2) return false;
  return (coordinate[0] - destinationLng).abs() <
          kDestinationMatchToleranceDegrees &&
      (coordinate[1] - destinationLat).abs() <
          kDestinationMatchToleranceDegrees;
}

/// Decide where the route should come from.
///
/// [locationService] is consulted **only** when a fetch is genuinely required
/// and no origin was supplied — never when a matching cached route exists.
Future<RouteSource> resolveRouteSource({
  required RouteResultModel? cachedRoute,
  required double destinationLat,
  required double destinationLng,
  required LocationService locationService,
  double? knownLat,
  double? knownLng,
}) async {
  if (cachedRoute != null &&
      cachedRoute.coordinates.isNotEmpty &&
      routeEndsAtDestination(
        cachedRoute.coordinates.last,
        destinationLng,
        destinationLat,
      )) {
    return CachedRouteSource(cachedRoute);
  }

  if (knownLat != null && knownLng != null) {
    return FetchRouteSource(originLat: knownLat, originLng: knownLng);
  }

  final position = await locationService.getCurrentPosition();
  if (position == null) return const AwaitingLocationRouteSource();

  return FetchRouteSource(
    originLat: position.latitude,
    originLng: position.longitude,
  );
}
