import '../../domain/entities/race_route.dart';

class RaceRouteModel extends RaceRoute {
  const RaceRouteModel({
    required super.id,
    required super.name,
    required super.coordinates,
    super.metadata,
  });

  factory RaceRouteModel.fromJson(Map<String, dynamic> json) {
    // GeoJSON usually has features
    final List features = json['features'] as List? ?? [];
    if (features.isEmpty) {
      throw Exception('Invalid GeoJSON: No features found');
    }

    final Map<String, dynamic> firstFeature = Map<String, dynamic>.from(features.first as Map);
    final Map<String, dynamic> geometry = Map<String, dynamic>.from(firstFeature['geometry'] as Map? ?? {});
    
    final List<List<double>> coordinates = (geometry['coordinates'] as List? ?? [])
        .map((e) => (e as List).map((coord) => (coord as num).toDouble()).toList())
        .toList();

    final Map<String, dynamic> properties = Map<String, dynamic>.from(firstFeature['properties'] as Map? ?? {});

    return RaceRouteModel(
      id: firstFeature['id']?.toString() ?? 'marathon_route',
      name: properties['name']?.toString() ?? 'Rio Marathon',
      coordinates: coordinates,
      metadata: properties,
    );
  }
}