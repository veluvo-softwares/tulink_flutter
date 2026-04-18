import 'package:equatable/equatable.dart';

/// Domain entity representing a place search result
class PlaceSearchResult extends Equatable {
  final String placeId;
  final String displayName;
  final String address;
  final double lat;
  final double lng;
  final List<String> types;

  const PlaceSearchResult({
    required this.placeId,
    required this.displayName,
    required this.address,
    required this.lat,
    required this.lng,
    required this.types,
  });

  @override
  List<Object?> get props => [
        placeId,
        displayName,
        address,
        lat,
        lng,
        types,
      ];
}