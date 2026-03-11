import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'widgets/map_journey_overlay.dart';
import 'widgets/map_header_overlay.dart';

class TulinkMapScreen extends StatefulWidget {
  const TulinkMapScreen({super.key});

  static const String routeName = "/mapview";

  @override
  State<TulinkMapScreen> createState() => _TulinkMapScreenState();
}

class _TulinkMapScreenState extends State<TulinkMapScreen> {
  MapboxMap? _mapboxMap;

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Standard Mapbox Map without custom datasets
          RepaintBoundary(
            child: MapWidget(
              key: const ValueKey("mapbox_map"),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.DARK,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(-43.1729, -22.9068)), // Center on Rio by default
                zoom: 12.0,
              ),
            ),
          ),
          
          // Map Header - Top Overlay
          const Align(
            alignment: Alignment.topCenter,
            child: MapHeaderOverlay(),
          ),
            
          // Map Bottom Bar - Bottom Overlay
          const Align(
            alignment: Alignment.bottomCenter,
            child: MapJourneyOverlay(),
          ),
        ],
      ),
    );
  }
}
