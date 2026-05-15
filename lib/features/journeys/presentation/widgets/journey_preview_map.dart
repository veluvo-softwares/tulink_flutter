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

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    // No point annotation manager needed — using style layers instead
    await _addJourneyDestinationPin();
    await _fitToJourney();
  }

  Future<void> _addJourneyDestinationPin() async {
    if (_mapboxMap == null) return;
    const sourceId = 'preview-dest-source';
    const ringId = 'preview-dest-ring';
    const dotId = 'preview-dest-dot';

    try { await _mapboxMap!.style.removeStyleLayer(ringId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleLayer(dotId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(sourceId); } catch (_) {}

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

      await _mapboxMap!.style.addLayer(CircleLayer(
        id: ringId,
        sourceId: sourceId,
        circleRadius: 14.0,
        circleColor: 0x33E8002D,
        circleStrokeColor: 0xFFE8002D,
        circleStrokeWidth: 2.5,
        circleOpacity: 1.0,
      ));

      await _mapboxMap!.style.addLayer(CircleLayer(
        id: dotId,
        sourceId: sourceId,
        circleRadius: 7.0,
        circleColor: 0xFFE8002D,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.0,
        circleOpacity: 1.0,
      ));

      print('✅ Journey preview destination pin rendered');
    } catch (e) {
      print('⚠️ Failed to render journey preview destination pin: $e');
    }
  }

  Future<void> _fitToJourney() async {
    if (_mapboxMap == null) return;
    await _mapboxMap!.setCamera(CameraOptions(
      center: Point(
        coordinates: Position(
          widget.journey.destination.longitude,
          widget.journey.destination.latitude,
        ),
      ),
      zoom: 13.0, // bumped for 180px container
    ));
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