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
}

class RouteResultModel {
  /// GeoJSON coordinates [[lng, lat], ...] — ready for Mapbox LineString source
  final List<List<double>> coordinates;
  final double distanceMetres;
  final double durationSeconds;
  final List<RouteStepModel> steps;

  const RouteResultModel({
    required this.coordinates,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.steps,
  });

  factory RouteResultModel.fromJson(Map<String, dynamic> json) {
    final rawCoords = json['coordinates'] as List<dynamic>? ?? [];
    final coordinates = rawCoords.map((c) {
      final pair = c as List<dynamic>;
      return [
        (pair[0] as num).toDouble(),
        (pair[1] as num).toDouble(),
      ];
    }).toList();

    final rawSteps = json['steps'] as List<dynamic>? ?? [];
    final steps = rawSteps
        .map((s) => RouteStepModel.fromJson(s as Map<String, dynamic>))
        .toList();

    return RouteResultModel(
      coordinates: coordinates,
      distanceMetres: (json['distanceMetres'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      steps: steps,
    );
  }
}
