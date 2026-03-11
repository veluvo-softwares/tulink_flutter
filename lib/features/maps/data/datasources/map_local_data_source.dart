import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/race_route_model.dart';

abstract class MapLocalDataSource {
  Future<RaceRouteModel> loadMarathonRoute();
}

class MapLocalDataSourceImpl implements MapLocalDataSource {
  static const String _marathonAssetPath = 'rio_marathon.geojson';

  @override
  Future<RaceRouteModel> loadMarathonRoute() async {
    // 1. Read the asset as a string
    final String geoJsonString = await rootBundle.loadString(_marathonAssetPath);
    
    // 2. Parse heavy JSON in a background isolate using compute
    return await compute(_parseGeoJson, geoJsonString);
  }

  static RaceRouteModel _parseGeoJson(String jsonString) {
    final Map<String, dynamic> data = json.decode(jsonString);
    return RaceRouteModel.fromJson(data);
  }
}