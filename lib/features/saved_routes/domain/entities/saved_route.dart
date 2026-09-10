import 'package:equatable/equatable.dart';

enum SavedRouteSource { computed, recorded, manual }

class SavedRouteWaypoint extends Equatable {
  const SavedRouteWaypoint({
    required this.latitude,
    required this.longitude,
    this.name,
  });

  final double latitude;
  final double longitude;
  final String? name;

  @override
  List<Object?> get props => [latitude, longitude, name];
}

class SavedRouteStep extends Equatable {
  const SavedRouteStep({
    required this.instruction,
    required this.distanceMetres,
    required this.maneuver,
  });

  final String instruction;
  final double distanceMetres;
  final String maneuver;

  @override
  List<Object?> get props => [instruction, distanceMetres, maneuver];
}

class SavedRoute extends Equatable {
  const SavedRoute({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.source,
    required this.geometry,
    required this.waypoints,
    required this.distanceMetres,
    required this.steps,
    required this.version,
    required this.canEdit,
    required this.editorUserIds,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.durationSeconds,
    this.createdByUserId,
  });

  final String id;
  final String organizationId;
  final String name;
  final String? description;
  final SavedRouteSource source;
  final List<List<double>> geometry;
  final List<SavedRouteWaypoint> waypoints;
  final double distanceMetres;
  final double? durationSeconds;
  final List<SavedRouteStep> steps;
  final int version;
  final String? createdByUserId;
  final bool canEdit;
  final List<String> editorUserIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavedRouteWaypoint get destination => waypoints.last;

  @override
  List<Object?> get props => [
    id,
    organizationId,
    name,
    description,
    source,
    geometry,
    waypoints,
    distanceMetres,
    durationSeconds,
    steps,
    version,
    createdByUserId,
    canEdit,
    editorUserIds,
    createdAt,
    updatedAt,
  ];
}
