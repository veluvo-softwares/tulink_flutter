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
  PointAnnotationManager? _pointAnnotationManager;

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = 
        await mapboxMap.annotations.createPointAnnotationManager();
    
    await _addJourneyMarkers();
    await _fitToJourney();
  }

  Future<void> _addJourneyMarkers() async {
    if (_mapboxMap == null || _pointAnnotationManager == null) return;

    // Clear previous annotations
    await _pointAnnotationManager?.deleteAll();

    // Add destination marker
    final destPos = Point(
      coordinates: Position(
        widget.journey.destination.longitude,
        widget.journey.destination.latitude,
      ),
    );
    
    await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: destPos,
      textField: 'DESTINATION',
      textColor: 0xFFE53E3E, // Electric Red
      textSize: 10,
      textOffset: [0, 2.0],
      iconImage: 'rocket-15',
    ));
  }

  Future<void> _fitToJourney() async {
    if (_mapboxMap == null) return;

    // Center on destination with appropriate zoom
    await _mapboxMap?.setCamera(CameraOptions(
      center: Point(
        coordinates: Position(
          widget.journey.destination.longitude,
          widget.journey.destination.latitude,
        ),
      ),
      zoom: 12,
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