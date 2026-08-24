import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Shared handle to the application's single Mapbox surface.
///
/// Exactly one `MapWidget` exists in TuLink. It is owned by the Home shell and
/// published through this controller so that any layer which needs to draw —
/// the destination draft, the live convoy, the completed-journey summary — can
/// do so without instantiating a map of its own.
///
/// Consumers must treat [map] as transient. A native surface can be torn down
/// and rebuilt (see [recreate]), and each rebuild bumps [generation]. Async work
/// must capture the generation it started under and discard itself if the value
/// has moved on, otherwise a late callback will draw onto a surface that no
/// longer corresponds to what the user is looking at.
class PersistentMapController extends ChangeNotifier {
  MapboxMap? _map;
  int _generation = 0;
  int _userPanTick = 0;
  bool _disposed = false;

  /// The generation whose restoration pass has already been claimed.
  ///
  /// Null until a surface has been restored at least once. Held here rather
  /// than in the shell so "restore exactly once per surface" is a property of
  /// the surface itself, and cannot be got wrong twice in two places.
  int? _restoredGeneration;

  /// The live Mapbox handle, or null while no surface is attached.
  MapboxMap? get map => _map;

  /// Incremented on every surface rebuild. Used to reject stale async work.
  int get generation => _generation;

  bool get isReady => _map != null;

  /// Increments whenever the user pans the map by hand. Layers that implement
  /// camera-follow watch this to yield control to the user; programmatic camera
  /// moves deliberately do not bump it.
  int get userPanTick => _userPanTick;

  /// Called by the map widget once the native surface reports ready.
  void attach(MapboxMap map) {
    if (_disposed) return;
    _map = map;
    notifyListeners();
  }

  /// Drop the current surface and force a new one to be built.
  ///
  /// Some devices resume from background with a black native surface even
  /// though Flutter keeps rendering. Rebuilding under a new [generation] gets a
  /// fresh surface, and layers restore their geometry when it reattaches.
  void recreate() {
    if (_disposed) return;
    _map = null;
    _generation++;
    notifyListeners();
  }

  /// Claim the restoration pass for the current surface.
  ///
  /// Returns true at most once per generation, and only while a surface is
  /// actually attached. Every layer restores its geometry off the resulting
  /// bump, so a second claim for the same generation would redraw everything a
  /// second time — which is what a resume looked like when two owners both
  /// thought they had to rebuild.
  bool claimRestoration() {
    if (_disposed || _map == null) return false;
    if (_restoredGeneration == _generation) return false;
    _restoredGeneration = _generation;
    return true;
  }

  /// True once the current surface has been restored.
  bool get isRestored => _map != null && _restoredGeneration == _generation;

  /// Report a user-initiated pan. Called from the map widget's scroll listener,
  /// which fires only for direct manipulation.
  void reportUserPan() {
    if (_disposed) return;
    _userPanTick++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _map = null;
    super.dispose();
  }
}
