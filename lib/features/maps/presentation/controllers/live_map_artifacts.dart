import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Every style source, layer and annotation the live convoy layer draws.
///
/// Collected in one place because these outlive the widget that created them:
/// they live on the *persistent* map surface, so nothing is reclaimed just
/// because `LiveJourneyExperience` was unmounted. Removing them is an explicit
/// act, not a side effect of disposal.
class LiveMapArtifactIds {
  const LiveMapArtifactIds._();

  /// Sources must be removed *after* every layer that references them.
  static const List<String> layers = [
    'actual-route-line',
    'actual-route-bg',
    'journey-destination-ring',
    'journey-destination-dot',
    'snapped-puck-ring',
    'snapped-puck-dot',
    'raw-puck-ring',
    'raw-puck-dot',
    'convoy-members-label-layer',
    'convoy-members-layer',
    'convoy-members-heading-layer',
  ];

  static const List<String> sources = [
    'actual-route-source',
    'journey-destination-source',
    'snapped-puck-source',
    'raw-puck-source',
    'convoy-members-source',
  ];
}

/// Removes the live convoy's drawings from the shared map surface.
///
/// Exists as an injectable port so cleanup can be asserted in tests without
/// Mapbox platform channels — the previous implementation relied on widget
/// `dispose`, which both ran too late to use the map channel and was
/// impossible to observe from a test.
abstract class LiveMapArtifacts {
  /// Remove every live artifact. Must be idempotent: it runs on completion, on
  /// journey switch, and defensively on teardown, and a missing layer is not an
  /// error.
  Future<void> clearAll();
}

/// Mapbox-backed implementation.
///
/// Each removal is individually guarded: Mapbox throws when asked to remove
/// something that was never added, and one absent layer must not abort the
/// rest of the cleanup — that is how a stale route survived onto the next
/// journey.
class MapboxLiveMapArtifacts implements LiveMapArtifacts {
  MapboxLiveMapArtifacts(this._map, {PointAnnotationManager? annotations})
    : _annotations = annotations;

  final MapboxMap _map;
  final PointAnnotationManager? _annotations;

  @override
  Future<void> clearAll() async {
    for (final layerId in LiveMapArtifactIds.layers) {
      try {
        await _map.style.removeStyleLayer(layerId);
      } catch (_) {
        // Not present — nothing to remove.
      }
    }
    for (final sourceId in LiveMapArtifactIds.sources) {
      try {
        await _map.style.removeStyleSource(sourceId);
      } catch (_) {
        // Not present — nothing to remove.
      }
    }
    try {
      await _annotations?.deleteAll();
    } catch (_) {
      // Manager already torn down with its surface.
    }
  }
}
