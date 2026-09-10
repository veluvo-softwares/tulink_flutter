import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';

/// Map styles available from the map's layer picker.
enum TulinkMapStyle {
  /// Road-focused default map.
  streets(
    label: 'Streets',
    icon: Icons.map_outlined,
    styleUri: MapboxStyles.MAPBOX_STREETS,
  ),

  /// Topographic map with trails and elevation detail.
  terrain(
    label: 'Terrain',
    icon: Icons.terrain_outlined,
    styleUri: MapboxStyles.OUTDOORS,
  ),

  /// Aerial imagery with road and place labels.
  satellite(
    label: 'Satellite',
    icon: Icons.satellite_alt_outlined,
    styleUri: MapboxStyles.SATELLITE_STREETS,
  );

  const TulinkMapStyle({
    required this.label,
    required this.icon,
    required this.styleUri,
  });

  /// User-facing name for the style.
  final String label;

  /// Icon displayed alongside the style.
  final IconData icon;

  /// Mapbox URI loaded for the style.
  final String styleUri;
}

/// Compact map-style menu shown over the persistent map.
class MapStyleSelector extends StatelessWidget {
  /// Creates a menu that reports the user's chosen map style.
  const MapStyleSelector({
    required this.selectedStyle,
    required this.onSelected,
    super.key,
    this.isLoading = false,
  });

  /// Style currently displayed by the map.
  final TulinkMapStyle selectedStyle;

  /// Called when the user chooses a different style.
  final ValueChanged<TulinkMapStyle> onSelected;

  /// Whether a replacement map surface is currently loading.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Material(
      color: colors.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<TulinkMapStyle>(
        tooltip: 'Change map type',
        enabled: !isLoading,
        initialValue: selectedStyle,
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        icon: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.deepTeal,
                ),
              )
            : Icon(Icons.layers_outlined, color: colors.deepTeal),
        itemBuilder: (context) => [
          for (final style in TulinkMapStyle.values)
            PopupMenuItem<TulinkMapStyle>(
              value: style,
              child: Row(
                children: [
                  Icon(style.icon, color: colors.deepTeal, size: 21),
                  const SizedBox(width: 12),
                  Expanded(child: Text(style.label)),
                  if (style == selectedStyle)
                    Icon(
                      Icons.check_rounded,
                      color: colors.routeTeal,
                      size: 20,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
