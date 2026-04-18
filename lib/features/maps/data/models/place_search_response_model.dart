import '../../domain/entities/place_search_result.dart';

class PlaceSearchResponseModel {
  final bool success;
  final int statusCode;
  final String message;
  final PlaceSearchDataModel data;

  const PlaceSearchResponseModel({
    required this.success,
    required this.statusCode,
    required this.message,
    required this.data,
  });

  factory PlaceSearchResponseModel.fromJson(Map<String, dynamic> json) {
    return PlaceSearchResponseModel(
      success: json['success'] as bool? ?? false,
      statusCode: (json['statusCode'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      data: PlaceSearchDataModel.fromJson(json['data'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'statusCode': statusCode,
      'message': message,
      'data': data.toJson(),
    };
  }
}

class PlaceSearchDataModel {
  final List<PlaceSearchResultModel> results;

  const PlaceSearchDataModel({
    required this.results,
  });

  factory PlaceSearchDataModel.fromJson(Map<String, dynamic> json) {
    final resultsJson = json['results'] as List<dynamic>? ?? [];
    return PlaceSearchDataModel(
      results: resultsJson
          .map((item) => PlaceSearchResultModel.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'results': results.map((result) => result.toJson()).toList(),
    };
  }
}

class PlaceSearchResultModel extends PlaceSearchResult {
  const PlaceSearchResultModel({
    required super.placeId,
    required super.displayName,
    required super.address,
    required super.lat,
    required super.lng,
    required super.types,
  });

  factory PlaceSearchResultModel.fromJson(Map<String, dynamic> json) {
    final typesList = json['types'] as List<dynamic>? ?? [];
    return PlaceSearchResultModel(
      placeId: json['placeId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      types: typesList.map((type) => type.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'placeId': placeId,
      'displayName': displayName,
      'address': address,
      'lat': lat,
      'lng': lng,
      'types': types,
    };
  }

  /// Convert model to domain entity
  PlaceSearchResult toDomain() => PlaceSearchResult(
        placeId: placeId,
        displayName: displayName,
        address: address,
        lat: lat,
        lng: lng,
        types: types,
      );
}