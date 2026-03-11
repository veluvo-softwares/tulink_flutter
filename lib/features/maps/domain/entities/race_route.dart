import 'package:equatable/equatable.dart';

class RaceRoute extends Equatable {
  final String id;
  final String name;
  final List<List<double>> coordinates;
  final Map<String, dynamic> metadata;

  const RaceRoute({
    required this.id,
    required this.name,
    required this.coordinates,
    this.metadata = const {},
  });

  @override
  List<Object?> get props => [id, name, coordinates, metadata];
}