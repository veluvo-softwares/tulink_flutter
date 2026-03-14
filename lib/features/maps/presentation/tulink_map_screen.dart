import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../journeys/presentation/providers/journey_provider.dart';
import 'widgets/map_journey_overlay.dart';
import 'widgets/map_header_overlay.dart';

class TulinkMapScreen extends StatefulWidget {
  const TulinkMapScreen({super.key});

  static const String routeName = '/mapview';

  @override
  State<TulinkMapScreen> createState() => _TulinkMapScreenState();
}

class _TulinkMapScreenState extends State<TulinkMapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = 
        await mapboxMap.annotations.createPointAnnotationManager();
    
    // Enable user location
    await mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
    ));

    await _updateMarkers();
  }

  Future<void> _updateMarkers() async {
    if (_mapboxMap == null || _pointAnnotationManager == null) return;

    // Clear previous annotations
    await _pointAnnotationManager?.deleteAll();

    // Sample journey participants for demonstration
    final sampleUsers = [
      {
        'name': 'John Doe',
        'lat': -1.2921,
        'lng': 36.8219,
        'index': 0,
        'isMe': true
      }, // Nairobi, Kenya
      {
        'name': 'Mary Jane Watson',
        'lat': -1.2845,
        'lng': 36.8310,
        'index': 1,
        'isMe': false
      }, // Westlands
      {
        'name': 'Peter Parker',
        'lat': -1.3032,
        'lng': 36.8256,
        'index': 2,
        'isMe': false
      }, // Karen
      {
        'name': 'Tony Stark',
        'lat': -1.2881,
        'lng': 36.8170,
        'index': 3,
        'isMe': false
      }, // Museum Hill
      {
        'name': 'Natasha Romanoff',
        'lat': -1.2815,
        'lng': 36.8023,
        'index': 4,
        'isMe': false
      }, // Kilimani
    ];

    // Add sample user markers demonstrating the new pin design
    // Note: Using PointAnnotation for now until ViewAnnotation 
    // integration is ready
    for (final userData in sampleUsers) {
      final userPos = Point(
        coordinates: Position(
          userData['lng']! as double,
          userData['lat']! as double,
        ),
      );
      
      // Create basic marker with color-coded text and icon
      await _pointAnnotationManager?.create(PointAnnotationOptions(
        geometry: userPos,
        textField: userData['name']! as String,
        textColor: userData['isMe']! as bool 
            ? Colors.red.toARGB32()  // Electric red for current user
            : _getUserAnnotationColor(userData['index']! as int),
        textSize: 11,
        textOffset: [0, 2.5],
        iconImage: 'marker-15', // Default Mapbox marker
      ));
    }

    // Add destination marker
    final destPos = Point(
      coordinates: Position(36.9066, -1.4210), // Kiambu destination
    );
    await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: destPos,
      textField: 'DESTINATION',
      textColor: Colors.orange.toARGB32(),
      textSize: 12,
      textOffset: [0, 2.5],
      iconImage: 'rocket-15',
    ));
  }

  // Helper method to get annotation colors matching UserPinUtils color scheme
  int _getUserAnnotationColor(int userIndex) {
    final colors = [
      0xFFE53E3E, // Red
      0xFF38A169, // Green  
      0xFFDD6B20, // Orange
      0xFF3182CE, // Blue
      0xFF805AD5, // Purple
      0xFFD69E2E, // Yellow
      0xFFE53E3E, // Pink (reusing red variant)
      0xFF319795, // Teal
    ];
    
    return colors[userIndex % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    // Listen to journey changes to update markers
    context.watch<JourneyProvider>().currentJourney;
    if (_mapboxMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateMarkers());
    }

    return Scaffold(
      body: Stack(
        children: [
          // Standard Mapbox Map without custom datasets
          RepaintBoundary(
            child: MapWidget(
              key: const ValueKey('mapbox_map'),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.DARK,
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: Position(36.8219, -1.2921), // Nairobi
                ),
                zoom: 7, // Zoom out to show more of Kenya
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
