import '../../../../core/common/result.dart';
import '../entities/place_search_result.dart';
import '../repositories/map_repository.dart';

class SearchPlacesUseCase {
  final MapRepository repository;

  SearchPlacesUseCase({required this.repository});

  Future<Result<List<PlaceSearchResult>>> call(
    String query, {
    double? lat,
    double? lng,
  }) async {
    return await repository.searchPlaces(query, lat: lat, lng: lng);
  }
}