import '../../domain/entities/saved_route.dart';

class SavedRouteModel extends SavedRoute {
  const SavedRouteModel({
    required super.id,
    required super.organizationId,
    required super.name,
    required super.source,
    required super.geometry,
    required super.waypoints,
    required super.distanceMetres,
    required super.steps,
    required super.version,
    required super.canEdit,
    required super.editorUserIds,
    required super.createdAt,
    required super.updatedAt,
    super.description,
    super.durationSeconds,
    super.createdByUserId,
  });

  factory SavedRouteModel.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source']?.toString().toLowerCase();
    return SavedRouteModel(
      id: json['id']?.toString() ?? '',
      organizationId: json['organizationId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Saved route',
      description: json['description']?.toString(),
      source: SavedRouteSource.values.firstWhere(
        (source) => source.name == sourceName,
        orElse: () => SavedRouteSource.manual,
      ),
      geometry: _geometry(json['geometry']),
      waypoints: _waypoints(json['waypoints']),
      distanceMetres: (json['distanceMetres'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
      steps: _steps(json['steps']),
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdByUserId: json['createdByUserId']?.toString(),
      canEdit: json['canEdit'] == true,
      editorUserIds: (json['editorUserIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static List<List<double>> _geometry(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<List<dynamic>>()
        .where((point) => point.length >= 2)
        .map(
          (point) => [
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ],
        )
        .toList(growable: false);
  }

  static List<SavedRouteWaypoint> _waypoints(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((value) {
          final point = value.cast<String, dynamic>();
          return SavedRouteWaypoint(
            latitude: (point['latitude'] as num).toDouble(),
            longitude: (point['longitude'] as num).toDouble(),
            name: point['name']?.toString(),
          );
        })
        .toList(growable: false);
  }

  static List<SavedRouteStep> _steps(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((value) {
          final step = value.cast<String, dynamic>();
          return SavedRouteStep(
            instruction: step['instruction']?.toString() ?? '',
            distanceMetres: (step['distanceMetres'] as num?)?.toDouble() ?? 0,
            maneuver: step['maneuver']?.toString() ?? '',
          );
        })
        .toList(growable: false);
  }
}
