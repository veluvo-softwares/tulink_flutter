class RouteStepModel {
  final String instruction;
  final double distanceMetres;
  final String maneuver;

  const RouteStepModel({
    required this.instruction,
    required this.distanceMetres,
    required this.maneuver,
  });

  factory RouteStepModel.fromJson(Map<String, dynamic> json) {
    return RouteStepModel(
      instruction: json['instruction']?.toString() ?? '',
      distanceMetres: (json['distanceMetres'] as num?)?.toDouble() ?? 0.0,
      maneuver: json['maneuver']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'instruction': instruction,
    'distanceMetres': distanceMetres,
    'maneuver': maneuver,
  };
}

class RouteResultModel {
  /// GeoJSON coordinates [[lng, lat], ...] — ready for Mapbox LineString source
  final List<List<double>> coordinates;
  final double distanceMetres;
  final double durationSeconds;
  final List<RouteStepModel> steps;

  /// Server-owned version for live convoy routes. Null for previews and
  /// legacy locally calculated routes.
  final int? canonicalVersion;

  /// Why the server created this canonical version.
  final String? canonicalReason;

  const RouteResultModel({
    required this.coordinates,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.steps,
    this.canonicalVersion,
    this.canonicalReason,
  });

  factory RouteResultModel.fromJson(Map<String, dynamic> json) {
    final rawCoords = json['coordinates'] as List<dynamic>? ?? [];
    final coordinates = <List<double>>[];
    for (final coordinate in rawCoords) {
      if (coordinate is! List || coordinate.length < 2) continue;
      final lng = coordinate[0];
      final lat = coordinate[1];
      if (lng is! num || lat is! num) continue;
      final longitude = lng.toDouble();
      final latitude = lat.toDouble();
      if (longitude < -180 ||
          longitude > 180 ||
          latitude < -90 ||
          latitude > 90) {
        continue;
      }
      coordinates.add([longitude, latitude]);
    }

    final rawSteps = json['steps'] as List<dynamic>? ?? [];
    final steps = rawSteps
        .whereType<Map<Object?, Object?>>()
        .map((s) => RouteStepModel.fromJson(s.cast<String, dynamic>()))
        .toList();

    return RouteResultModel(
      coordinates: coordinates,
      distanceMetres: (json['distanceMetres'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      steps: steps,
      canonicalVersion: (json['version'] as num?)?.toInt(),
      canonicalReason: json['reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'coordinates': coordinates,
    'distanceMetres': distanceMetres,
    'durationSeconds': durationSeconds,
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
    if (canonicalVersion != null) 'version': canonicalVersion,
    if (canonicalReason != null) 'reason': canonicalReason,
  };
}
