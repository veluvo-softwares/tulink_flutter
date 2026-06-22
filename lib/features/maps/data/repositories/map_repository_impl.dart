import '../../../../core/common/result.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/race_route.dart';
import '../../domain/entities/place_search_result.dart';
import '../../domain/repositories/map_repository.dart';
import '../datasources/map_local_data_source.dart';
import '../datasources/place_search_remote_data_source.dart';

class MapRepositoryImpl implements MapRepository {
  final MapLocalDataSource localDataSource;
  final PlaceSearchRemoteDataSource placeSearchRemoteDataSource;

  MapRepositoryImpl({
    required this.localDataSource,
    required this.placeSearchRemoteDataSource,
  });

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
          return ResultHelper.failure(
            SearchFailure.noResults(trimmedQuery),
          );
        }
        
        return ResultHelper.success(places);
      } else {
        // Handle different server response types
        if (response.statusCode == 400) {
          return ResultHelper.failure(
            SearchFailure.invalidQuery(trimmedQuery),
          );
        } else if (response.statusCode == 403) {
          return ResultHelper.failure(
            SearchFailure.accessDenied,
          );
        } else if (response.statusCode == 404) {
          return ResultHelper.failure(
            SearchFailure.serviceUnavailable,
          );
        } else if (response.statusCode == 429) {
          return ResultHelper.failure(
            SearchFailure.rateLimitExceeded,
          );
        } else {
          return ResultHelper.failure(
            ServerFailure(message: 'Something went wrong :(\nPlease try again in a moment'),
          );
        }
      }
    } catch (e) {
      return ResultHelper.failure(
        NetworkFailure.searchConnection,
      );
    }
  }
}
