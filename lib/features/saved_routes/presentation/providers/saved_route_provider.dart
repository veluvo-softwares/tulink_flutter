import 'package:flutter/foundation.dart';

import '../../../../core/common/result.dart';
import '../../domain/entities/saved_route.dart';
import '../../domain/repositories/saved_route_repository.dart';

class SavedRouteProvider extends ChangeNotifier {
  SavedRouteProvider(this._repository);

  final SavedRouteRepository _repository;
  List<SavedRoute> _routes = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  List<SavedRoute> get routes => List.unmodifiable(_routes);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final result = await _repository.list();
    _routes = result.data ?? const [];
    _error = result.failure?.message;
    _isLoading = false;
    notifyListeners();
  }

  Future<SavedRoute?> create({
    required String name,
    String? description,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    final result = await _repository.create(
      name: name,
      description: description,
      source: source,
      waypoints: waypoints,
      geometry: geometry,
      routeIndex: routeIndex,
      recordedDurationSeconds: recordedDurationSeconds,
    );
    final route = result.data;
    if (route != null) _routes = [route, ..._routes];
    _error = result.failure?.message;
    _isSaving = false;
    notifyListeners();
    return route;
  }

  Future<bool> archive(String id) async {
    final result = await _repository.archive(id);
    if (result.isSuccess) {
      _routes = _routes.where((route) => route.id != id).toList();
      notifyListeners();
      return true;
    }
    _error = result.failure?.message;
    notifyListeners();
    return false;
  }

  Future<SavedRoute?> update({
    required SavedRoute existing,
    required String name,
    required SavedRouteSource source,
    required List<SavedRouteWaypoint> waypoints,
    List<List<double>>? geometry,
    int routeIndex = 0,
    double? recordedDurationSeconds,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    final result = await _repository.update(
      id: existing.id,
      expectedVersion: existing.version,
      name: name,
      description: existing.description,
      source: source,
      waypoints: waypoints,
      geometry: geometry,
      routeIndex: routeIndex,
      recordedDurationSeconds: recordedDurationSeconds,
    );
    final route = result.data;
    if (route != null) {
      _routes = _routes
          .map((candidate) => candidate.id == route.id ? route : candidate)
          .toList(growable: false);
    }
    _error = result.failure?.message;
    _isSaving = false;
    notifyListeners();
    return route;
  }
}
