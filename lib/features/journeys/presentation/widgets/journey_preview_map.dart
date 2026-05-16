import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../domain/entities/journey.dart';

class JourneyPreviewMap extends StatefulWidget {
  final Journey journey;

  const JourneyPreviewMap({
    super.key,
    required this.journey,
  });

  @override
  State<JourneyPreviewMap> createState() => _JourneyPreviewMapState();
}

class _JourneyPreviewMapState extends State<JourneyPreviewMap> {
  MapboxMap? _mapboxMap;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _mapboxMap = null;
    super.dispose();
  }

  /// Whether it's safe to call into the native Mapbox channel.
  /// The platform channel is torn down on dispose, so any call after that
  /// throws PlatformException("Unable to establish connection on channel").
  bool get _canUseMap => !_disposed && mounted && _mapboxMap != null;

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    if (_disposed) return;
    _mapboxMap = mapboxMap;
    await _addJourneyDestinationPin();
    if (!_canUseMap) return;
    await _fitToJourney();
  }

  Future<void> _addJourneyDestinationPin() async {
    if (!_canUseMap) return;
    const sourceId = 'preview-dest-source';
    const ringId = 'preview-dest-ring';
    const dotId = 'preview-dest-dot';

    try { await _mapboxMap!.style.removeStyleLayer(ringId); } catch (_) {}
    if (!_canUseMap) return;
    try { await _mapboxMap!.style.removeStyleLayer(dotId); } catch (_) {}
    if (!_canUseMap) return;
    try { await _mapboxMap!.style.removeStyleSource(sourceId); } catch (_) {}
    if (!_canUseMap) return;

    try {
      final geoJson = jsonEncode({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'Point',
          'coordinates': [
            widget.journey.destination.longitude,
            widget.journey.destination.latitude,
          ],
        },
      });

      await _mapboxMap!.style.addSource(
        GeoJsonSource(id: sourceId, data: geoJson),
      );
      if (!_canUseMap) return;

      await _mapboxMap!.style.addLayer(CircleLayer(
        id: ringId,
        sourceId: sourceId,
        circleRadius: 14.0,
        circleColor: 0x33E8002D,
        circleStrokeColor: 0xFFE8002D,
        circleStrokeWidth: 2.5,
        circleOpacity: 1.0,
      ));
      if (!_canUseMap) return;

      await _mapboxMap!.style.addLayer(CircleLayer(
        id: dotId,
        sourceId: sourceId,
        circleRadius: 7.0,
        circleColor: 0xFFE8002D,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.0,
        circleOpacity: 1.0,
      ));
    } catch (e) {
      if (_disposed) return;
      debugPrint('⚠️ Failed to render journey preview destination pin: $e');
    }
  }

  Future<void> _fitToJourney() async {
    if (!_canUseMap) return;
    try {
      await _mapboxMap!.setCamera(CameraOptions(
        center: Point(
          coordinates: Position(
            widget.journey.destination.longitude,
            widget.journey.destination.latitude,
          ),
        ),
        zoom: 13.0,
      ));
    } catch (e) {
      if (_disposed) return;
      debugPrint('⚠️ Failed to fit journey preview camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: MapWidget(
          key: ValueKey('journey_preview_${widget.journey.id}'),
          onMapCreated: _onMapCreated,
          styleUri: MapboxStyles.DARK,
          cameraOptions: CameraOptions(
            center: Point(
              coordinates: Position(
                widget.journey.destination.longitude,
                widget.journey.destination.latitude,
              ),
            ),
            zoom: 12,
          ),
        ),
      ),
    );
  }
}