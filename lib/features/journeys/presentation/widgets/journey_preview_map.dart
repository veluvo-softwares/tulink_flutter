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
    
    // Add destination marker
    await _addDestinationMarker();
    
    // Center map on destination
    await _centerMapOnDestination();
  }

  Future<void> _addDestinationMarker() async {
    if (_pointAnnotationManager == null) {
      return;
    }

    final destination = widget.journey.destination;
    
    // Create destination marker
    final destPos = Point(
      coordinates: Position(
        destination.longitude,
        destination.latitude,
      ),
    );

    await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: destPos,
      textField: 'DESTINATION',
      textColor: 0xFFFF6B35, // Orange color
      textSize: 12,
      textOffset: [0, 2.5],
      iconImage: 'marker-15', // Default Mapbox marker
      iconSize: 1.2,
    ));
  }

  Future<void> _centerMapOnDestination() async {
    if (_mapboxMap == null) {
      return;
    }

    final destination = widget.journey.destination;
    
    await _mapboxMap!.setCamera(CameraOptions(
      center: Point(
        coordinates: Position(
          destination.longitude,
          destination.latitude,
        ),
      ),
      zoom: 12.0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mapbox Map
        MapWidget(
          key: const ValueKey('journey_preview_map'),
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

        // Map overlay with journey info
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.journey.destinationAddress ?? 'Destination',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Map controls
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            children: [
              // Zoom in button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () async {
                    final currentState = await _mapboxMap?.getCameraState();
                    _mapboxMap?.setCamera(CameraOptions(
                      zoom: (currentState?.zoom ?? 12) + 1,
                    ));
                  },
                  icon: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Zoom out button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () async {
                    final currentState = await _mapboxMap?.getCameraState();
                    _mapboxMap?.setCamera(CameraOptions(
                      zoom: (currentState?.zoom ?? 12) - 1,
                    ));
                  },
                  icon: const Icon(
                    Icons.remove,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}