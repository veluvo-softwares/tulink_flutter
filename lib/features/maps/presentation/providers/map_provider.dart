import 'package:flutter/foundation.dart';
import '../../../../core/common/result.dart';
import '../../domain/entities/place_search_result.dart';
import '../../domain/entities/race_route.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/usecases/search_places_usecase.dart';

class MapProvider with ChangeNotifier {
  final MapRepository _repository;
  final SearchPlacesUseCase _searchPlacesUseCase;

  MapProvider(this._repository, this._searchPlacesUseCase);

  RaceRoute? _marathonRoute;
  bool _isLoading = false;
  String? _error;
  
  List<PlaceSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  RaceRoute? get marathonRoute => _marathonRoute;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<PlaceSearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  Future<void> loadMarathonData() async {
    // Marathon data is deprecated
    _marathonRoute = null;
    notifyListeners();
  }
  
  Future<void> searchPlaces(String query) async {
    final trimmedQuery = query.trim();
    
    // Clear results if query is empty or too short
    if (trimmedQuery.isEmpty || trimmedQuery.length < 2) {
      _searchResults = [];
      _searchError = null;
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    final result = await _searchPlacesUseCase(trimmedQuery);
    
    _isSearching = false;
    
    if (result.isSuccess && result.data != null) {
      _searchResults = result.data!;
      _searchError = null;
    } else if (result.isFailure && result.failure != null) {
      _searchResults = [];
      _searchError = result.failure!.message;
    }
    
    notifyListeners();
  }
  
  void clearSearchResults() {
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }
}
