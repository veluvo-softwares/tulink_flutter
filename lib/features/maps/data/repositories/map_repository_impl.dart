import 'package:dio/dio.dart';

import '../../../../core/common/result.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/race_route.dart';
import '../../domain/entities/place_search_result.dart';
import '../../domain/repositories/map_repository.dart';
import '../datasources/map_local_data_source.dart';
import '../datasources/place_search_remote_data_source.dart';
import '../datasources/route_remote_data_source.dart';
import '../models/route_result_model.dart';
import '../../../../core/services/connectivity_service.dart';

class MapRepositoryImpl implements MapRepository {
  final MapLocalDataSource localDataSource;
  final PlaceSearchRemoteDataSource placeSearchRemoteDataSource;
  final RouteRemoteDataSource routeRemoteDataSource;
  final ConnectivityService connectivityService;

  MapRepositoryImpl({
    required this.localDataSource,
    required this.placeSearchRemoteDataSource,
    required this.routeRemoteDataSource,
    required this.connectivityService,
  });

  /// The route already stored for this journey, if one matches the
  /// destination.
  ///
  /// Separate from [getRoute] because a Future resolves once and so cannot
  /// both draw immediately and refresh afterwards. Callers draw this while the
  /// live route is fetched. Returns null when nothing usable is stored — the
  /// same shape as [getRoute], so a caller can fall through without special
  /// casing.
  @override
  Future<RouteResultModel?> getCachedRoute({
    required String userId,
    required String journeyId,
    required double destinationLat,
    required double destinationLng,
  }) => localDataSource.loadRoute(
    userId: userId,
    journeyId: journeyId,
    destinationLat: destinationLat,
    destinationLng: destinationLng,
  );

  @override
  Future<RouteResultModel?> getRoute({
    required String userId,
    required String journeyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    if (!connectivityService.isOnline.value) {
      return localDataSource.loadRoute(
        userId: userId,
        journeyId: journeyId,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
      );
    }

    final remote = await routeRemoteDataSource.getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destinationLat,
      destLng: destinationLng,
    );
    if (remote != null) {
      await localDataSource.saveRoute(
        userId: userId,
        journeyId: journeyId,
        originLat: originLat,
        originLng: originLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        route: remote,
      );
      return remote;
    }

    return localDataSource.loadRoute(
      userId: userId,
      journeyId: journeyId,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
  }

  @override
  Future<RaceRoute?> getMarathonRoute() async {
    return await localDataSource.loadMarathonRoute();
  }

  @override
  Future<Result<List<PlaceSearchResult>>> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    String? regionCode,
  }) async {
    try {
      final trimmedQuery = query.trim();
      if (trimmedQuery.isEmpty || trimmedQuery.length < 2) {
        return ResultHelper.success(<PlaceSearchResult>[]);
      }

      final response = await placeSearchRemoteDataSource.searchPlaces(
        trimmedQuery,
        lat: lat,
        lng: lng,
        regionCode: regionCode,
      );

      if (response.success) {
        final places = response.data.results
            .map((model) => model.toDomain())
            .toList();

        // Return no results failure if empty
        if (places.isEmpty) {
          return ResultHelper.failure(SearchFailure.noResults(trimmedQuery));
        }

        return ResultHelper.success(places);
      } else {
        // Handle different server response types
        if (response.statusCode == 400) {
          return ResultHelper.failure(SearchFailure.invalidQuery(trimmedQuery));
        } else if (response.statusCode == 403) {
          return ResultHelper.failure(SearchFailure.accessDenied);
        } else if (response.statusCode == 404) {
          return ResultHelper.failure(SearchFailure.serviceUnavailable);
        } else if (response.statusCode == 429) {
          return ResultHelper.failure(SearchFailure.rateLimitExceeded);
        } else {
          return ResultHelper.failure(
            ServerFailure(
              message: 'Something went wrong :(\nPlease try again in a moment',
            ),
          );
        }
      }
    } on DioException catch (e) {
      // Aborted/superseded request (FIX-05 CancelToken) — benign, never an error card.
      if (e.type == DioExceptionType.cancel) {
        return ResultHelper.failure(SearchFailure.cancelled);
      }
      // Genuine connectivity problems → the "check your internet" message is correct.
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return ResultHelper.failure(NetworkFailure.searchConnection);
      }
      // Any other Dio failure (badResponse/5xx/unknown) is a SERVER problem, not
      // offline — do NOT show the connectivity card while the device is online.
      return ResultHelper.failure(
        ServerFailure(
          message: 'Search failed :(\nPlease try again in a moment',
        ),
      );
    } on FormatException {
      // Malformed/unexpected body — a data/server problem, not connectivity.
      return ResultHelper.failure(
        ServerFailure(
          message: 'Search failed :(\nPlease try again in a moment',
        ),
      );
    } catch (e) {
      // Parse/type errors (e.g. unexpected response shape) — server/data problem,
      // not "no internet".
      return ResultHelper.failure(
        ServerFailure(
          message: 'Search failed :(\nPlease try again in a moment',
        ),
      );
    }
  }
}
