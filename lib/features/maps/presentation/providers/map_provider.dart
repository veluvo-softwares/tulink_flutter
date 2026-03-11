import 'package:flutter/foundation.dart';
import '../../domain/entities/race_route.dart';
import '../../domain/repositories/map_repository.dart';

class MapProvider with ChangeNotifier {
  final MapRepository _repository;

  MapProvider(this._repository);

  RaceRoute? _marathonRoute;
  bool _isLoading = false;
  String? _error;

  RaceRoute? get marathonRoute => _marathonRoute;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadMarathonData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _marathonRoute = await _repository.getMarathonRoute();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}