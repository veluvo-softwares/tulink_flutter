import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/services/offline_storage_service.dart';
import '../models/route_result_model.dart';

class OfflineMapEstimate {
  const OfflineMapEstimate({
    required this.transferBytes,
    required this.storageBytes,
    required this.errorMargin,
  });

  final int transferBytes;
  final int storageBytes;
  final double errorMargin;
}

class OfflineMapService {
  OfflineMapService(this._storage);

  static const int diskQuotaBytes = 1024 * 1024 * 1024;
  static const double corridorRadiusMetres = 1000;
  static const double minZoom = 8;
  static const double maxZoom = 16;

  final OfflineStorageService _storage;
  OfflineManager? _offlineManager;
  TileStore? _tileStore;

  Future<void> init() async {
    _offlineManager = await OfflineManager.create();
    _tileStore = await TileStore.createDefault();
    _tileStore!.setDiskQuota(diskQuotaBytes);
  }

  Future<OfflineMapEstimate> estimateRoute({
    required String userId,
    required String journeyId,
    required RouteResultModel route,
    bool wifiOnly = true,
  }) async {
    final result = await _requireTileStore().estimateTileRegion(
      _regionId(userId, journeyId),
      _options(userId, journeyId, route, wifiOnly),
      TileRegionEstimateOptions(
        errorMargin: 0.05,
        preciseEstimationTimeout: 5,
        timeout: 30,
      ),
      null,
    );
    return OfflineMapEstimate(
      transferBytes: result.transferSize,
      storageBytes: result.storageSize,
      errorMargin: result.errorMargin,
    );
  }

  Future<void> downloadRoute({
    required String userId,
    required String journeyId,
    required RouteResultModel route,
    bool wifiOnly = true,
    void Function(double progress)? onProgress,
  }) async {
    final manager = _offlineManager;
    if (manager == null)
      throw StateError('OfflineMapService is not initialized');
    await manager.loadStylePack(
      MapboxStyles.DARK,
      StylePackLoadOptions(
        glyphsRasterizationMode:
            GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        metadata: {'owner': 'tulink-offline'},
        acceptExpired: false,
      ),
      null,
    );
    final regionId = _regionId(userId, journeyId);
    final region = await _requireTileStore().loadTileRegion(
      regionId,
      _options(userId, journeyId, route, wifiOnly),
      (progress) {
        final required = progress.requiredResourceCount;
        onProgress?.call(
          required == 0 ? 0 : progress.completedResourceCount / required,
        );
      },
    );
    final complete =
        region.requiredResourceCount > 0 &&
        region.completedResourceCount == region.requiredResourceCount;
    await _storage.tileMetadata.put(_metadataKey(userId, journeyId), {
      'schemaVersion': 1,
      'userId': userId,
      'journeyId': journeyId,
      'regionId': regionId,
      'styleUri': MapboxStyles.DARK,
      'requiredResourceCount': region.requiredResourceCount,
      'completedResourceCount': region.completedResourceCount,
      'completedResourceSize': region.completedResourceSize,
      'complete': complete,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _storage.mergeSession(userId, journeyId, {
      'mapStyleUri': MapboxStyles.DARK,
      'tileRegionIds': [regionId],
      'offlineMapComplete': complete,
    });
    if (!complete) throw StateError('Mapbox tile region is incomplete');
    onProgress?.call(1);
  }

  Future<void> cancelDownload(String userId, String journeyId) async {
    await _requireTileStore().removeRegion(_regionId(userId, journeyId));
  }

  Future<void> deleteRouteRegion(String userId, String journeyId) async {
    final regionId = _regionId(userId, journeyId);
    await _requireTileStore().removeRegion(regionId);
    await _storage.tileMetadata.delete(_metadataKey(userId, journeyId));
    await _storage.mergeSession(userId, journeyId, {
      'tileRegionIds': <String>[],
      'offlineMapComplete': false,
    });
  }

  Map<String?, Object?> _corridorGeometry(RouteResultModel route) {
    if (route.coordinates.length < 2) {
      throw ArgumentError('A route needs at least two coordinates');
    }
    final polygons = <Object?>[];
    for (var index = 0; index < route.coordinates.length - 1; index++) {
      final start = route.coordinates[index];
      final end = route.coordinates[index + 1];
      if (start.length < 2 || end.length < 2) continue;
      polygons.add([_segmentRing(start, end)]);
    }
    return <String?, Object?>{'type': 'MultiPolygon', 'coordinates': polygons};
  }

  List<List<double>> _segmentRing(List<double> start, List<double> end) {
    final meanLatRadians = ((start[1] + end[1]) / 2) * math.pi / 180;
    final metresPerLngDegree = math.max(
      111320 * math.cos(meanLatRadians).abs(),
      1000,
    );
    final dx = (end[0] - start[0]) * metresPerLngDegree;
    final dy = (end[1] - start[1]) * 110540;
    final length = math.max(math.sqrt(dx * dx + dy * dy), 1);
    final offsetLng =
        (-dy / length) * corridorRadiusMetres / metresPerLngDegree;
    final offsetLat = (dx / length) * corridorRadiusMetres / 110540;
    return [
      [start[0] + offsetLng, start[1] + offsetLat],
      [end[0] + offsetLng, end[1] + offsetLat],
      [end[0] - offsetLng, end[1] - offsetLat],
      [start[0] - offsetLng, start[1] - offsetLat],
      [start[0] + offsetLng, start[1] + offsetLat],
    ];
  }

  TileRegionLoadOptions _options(
    String userId,
    String journeyId,
    RouteResultModel route,
    bool wifiOnly,
  ) => TileRegionLoadOptions(
    geometry: _corridorGeometry(route),
    descriptorsOptions: [
      TilesetDescriptorOptions(
        styleURI: MapboxStyles.DARK,
        minZoom: minZoom,
        maxZoom: maxZoom,
        pixelRatio: 1,
      ),
    ],
    metadata: {'userId': userId, 'journeyId': journeyId},
    acceptExpired: true,
    networkRestriction: wifiOnly
        ? NetworkRestriction.DISALLOW_EXPENSIVE
        : NetworkRestriction.NONE,
  );

  TileStore _requireTileStore() =>
      _tileStore ?? (throw StateError('OfflineMapService is not initialized'));

  String _regionId(String userId, String journeyId) =>
      'tulink-route-$userId-$journeyId';

  String _metadataKey(String userId, String journeyId) =>
      '${StorageKeys.offlineTilePrefix}$userId:$journeyId';
}
