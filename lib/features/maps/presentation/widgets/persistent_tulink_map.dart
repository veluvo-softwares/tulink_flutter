import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../controllers/persistent_map_controller.dart';

/// The application's only `MapWidget`.
///
/// Every map-bearing surface in TuLink renders through this one instance. Map
/// state — camera, route, destination, convoy markers — therefore survives
/// moving between exploring, drafting and a live convoy, instead of each screen
/// standing up its own map and re-deriving the same geometry from scratch.
///
/// If you find yourself needing a map somewhere else, host this widget's
/// controller rather than adding a second `MapWidget`; a second native surface
/// costs a full renderer and reintroduces the state divergence this exists to
/// prevent.
class PersistentTulinkMap extends StatelessWidget {
  const PersistentTulinkMap({
    super.key,
    required this.controller,
    this.initialCamera,
  });

  final PersistentMapController controller;
  final CameraOptions? initialCamera;

  @override
  Widget build(BuildContext context) {
    // Keyed by generation so `recreate()` produces a genuinely new native
    // surface rather than reusing the one that came back black.
    return RepaintBoundary(
      child: MapWidget(
        key: ValueKey('tulink_persistent_map_${controller.generation}'),
        onMapCreated: controller.attach,
        // Fires only for direct manipulation, never for programmatic camera
        // moves, so camera-follow can yield to the user without a guard flag.
        onScrollListener: (_) => controller.reportUserPan(),
        styleUri: MapboxStyles.MAPBOX_STREETS,
        cameraOptions:
            initialCamera ??
            CameraOptions(
              center: Point(coordinates: Position(36.8219, -1.2921)),
              zoom: 10.5,
            ),
      ),
    );
  }
}
